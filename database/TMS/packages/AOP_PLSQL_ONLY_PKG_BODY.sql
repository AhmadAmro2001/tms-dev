
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."AOP_PLSQL_ONLY_PKG" as

/**
 * @Description: Package to show how to make a manual call with PL/SQL to the AOP Server
 *               If APEX is not installed, you can use this package as your starting point but you would need to change the apex_web_service calls by utl_http calls or similar.
 *
 * @Author: Dimitri Gielis
 * @Created: 12/12/2015
 */

function replace_with_clob(
   p_source in clob
  ,p_search in varchar2
  ,p_replace in clob
) return clob
as
  l_pos pls_integer;
begin
  l_pos := instr(p_source, p_search);
  if l_pos > 0 then
    return substr(p_source, 1, l_pos-1)
      || p_replace
      || substr(p_source, l_pos+length(p_search));
  end if;
  return p_source;
end replace_with_clob;


function blob2clobbase64(p_blob in blob)
return clob
as
  l_step   pls_integer := 12000;
  l_base64 clob;
begin
  for i in 0 .. trunc((dbms_lob.getlength(p_blob) - 1 )/l_step) loop
    l_base64 := l_base64 || sys.utl_raw.cast_to_varchar2(sys.utl_encode.base64_encode(dbms_lob.substr(p_blob, l_step, i * l_step + 1)));
  end loop;

  return l_base64;
end blob2clobbase64;


--
function make_aop_request(
  p_aop_url            in varchar2 default g_aop_url,
  p_api_key            in varchar2 default g_api_key,
  p_aop_mode           in varchar2 default g_aop_mode,
  p_data_json          in clob,
  p_template           in blob default null,
  p_template_type      in varchar2 default null,
  p_output_type        in varchar2 default null,
  p_output_filename    in varchar2 default 'output',
  p_aop_debug          in varchar2 default 'No',
  p_prepend_files_json in clob default null,
  p_append_files_json  in clob default null,
  p_templates_json     in clob default null,
  p_output_json        in clob default null)
  return blob
as
  l_aop_json          clob;
  l_template_clob     clob;
  l_template_type     varchar2(10);
  l_output_type       varchar2(10);
  l_blob              blob;
  l_error_description varchar2(32767);
  l_max_amount        integer := dbms_lob.lobmaxsize;
  l_amount            binary_integer := 8000;
  l_dest_offset       integer := 1 ;
  l_src_offset        integer := 1 ;
  l_blob_csid         integer := dbms_lob.default_csid;
  l_lang_context      integer := dbms_lob.default_lang_ctx;
  l_warning           integer := dbms_lob.warn_inconvertible_char;
  l_req               utl_http.req;
  l_res               utl_http.resp;
  l_buffer            varchar2(32767);
  l_raw_buf           raw(32767);
  l_step              pls_integer := 12000;
  l_head_name         varchar2(4000);
  l_head_value        varchar2(32767);
  l_output_json       clob;
  l_aop_json_length   integer;
begin
  if p_template is not null
  then
    l_template_clob := blob2clobbase64(p_template);
    l_template_clob := replace(l_template_clob, chr(13) || chr(10), null);
    l_template_clob := replace(l_template_clob, '"', '\u0022');
  end if;

  if p_template_type is not null
  then
    l_template_type := p_template_type;
  elsif p_template_type is null and p_template is not null
  then
    if dbms_lob.instr(p_template, utl_raw.cast_to_raw('ppt/presentation'))> 0
    then
      l_template_type := 'pptx';
    elsif dbms_lob.instr(p_template, utl_raw.cast_to_raw('worksheets/'))> 0
    then
      l_template_type := 'xlsx';
    elsif dbms_lob.instr(p_template, utl_raw.cast_to_raw('word/document'))> 0
    then
      l_template_type := 'docx';
    elsif dbms_lob.instr(p_template, utl_raw.cast_to_raw('html'))> 0
    then
      l_template_type := 'html';
    else
      l_template_type := 'txt';
    end if;
  else
    -- use AOP Template
    l_template_type := '';
  end if;

  if p_output_type is null
  then
    l_output_type := l_template_type;
  else
    l_output_type := p_output_type;
  end if;

  if p_output_json is null
  then
    l_output_json := ' "output_converter": "' || g_output_converter || '" ';
  else
    l_output_json := ' "output_converter": "' || g_output_converter || '", ' || p_output_json;
  end if;

  l_aop_json := '
  {
      "version": "***AOP_VERSION***",
      "api_key": "***AOP_API_KEY***",
      "mode": "***AOP_MODE***",
      "template": {
        "file":"***AOP_TEMPLATE_BASE64***",
         "template_type": "***AOP_TEMPLATE_TYPE***"
      },
      "templates":
        ***AOP_TEMPLATES_JSON***,
      "output": {
        "output_encoding": "raw",
        "output_type": "***AOP_OUTPUT_TYPE***",
        ***AOP_OUTPUT_JSON***
      },
      "files":
        ***AOP_DATA_JSON***,
      "prepend_files":
        ***AOP_PREPEND_FILES_JSON***,
      "append_files":
        ***AOP_APPEND_FILES_JSON***
  }';

  l_aop_json := replace(l_aop_json, '***AOP_VERSION***', c_aop_version);
  l_aop_json := replace(l_aop_json, '***AOP_API_KEY***', p_api_key);
  l_aop_json := replace(l_aop_json, '***AOP_MODE***', p_aop_mode);
  l_aop_json := replace_with_clob(l_aop_json, '***AOP_TEMPLATE_BASE64***', l_template_clob);
  l_aop_json := replace_with_clob(l_aop_json, '***AOP_TEMPLATE_TYPE***', l_template_type);
  l_aop_json := replace(l_aop_json, '***AOP_OUTPUT_TYPE***', l_output_type);
  l_aop_json := replace(l_aop_json, '***AOP_OUTPUT_JSON***', l_output_json);
  l_aop_json := replace_with_clob(l_aop_json, '***AOP_DATA_JSON***', p_data_json);
  l_aop_json := replace_with_clob(l_aop_json, '***AOP_PREPEND_FILES_JSON***', nvl(p_prepend_files_json,'[]'));
  l_aop_json := replace_with_clob(l_aop_json, '***AOP_APPEND_FILES_JSON***', nvl(p_append_files_json,'[]'));
  l_aop_json := replace_with_clob(l_aop_json, '***AOP_TEMPLATES_JSON***', nvl(p_templates_json,'[]'));
  l_aop_json := replace(l_aop_json, '\\n', '\n');
  dbms_lob.createtemporary(l_blob, false);
  dbms_lob.converttoblob (
        dest_lob    => l_blob,
        src_clob    => l_aop_json,
        amount      => l_max_amount,
        dest_offset => l_dest_offset,
        src_offset  => l_src_offset,
        blob_csid   => l_blob_csid,
        lang_context=> l_lang_context,
        warning     => l_warning
    );
  if p_aop_debug != 'Local'
  then
    -- If using HTTPS, open a wallet containing the trusted root certificate.
    if g_wallet_path is not null
      -- and g_wallet_pwd is not null
    then
      sys.utl_http.set_wallet(g_wallet_path, g_wallet_pwd);
    end if;

    -- Call AOP
    l_aop_json_length := sys.dbms_lob.getlength(l_blob);
    l_req := sys.utl_http.begin_request(p_aop_url, 'POST', 'HTTP/1.1');
    sys.utl_http.set_header(l_req, 'Content-Type', 'application/json');
    sys.utl_http.set_header(l_req, 'Content-Length', l_aop_json_length);

    if l_aop_json_length > 0 then
        declare
            l_raw              raw(8000);
            l_amount           number := 8000;
            l_offset           number := 1;
        begin
            while (l_offset <= l_aop_json_length) loop
                sys.dbms_lob.read(l_blob, l_amount, l_offset, l_raw);
                sys.utl_http.write_raw(l_req, l_raw);
                l_offset := l_offset + l_amount;
            end loop;
        end;
    end if;


    l_res := sys.utl_http.get_response(l_req);
    -- code and header
    if l_res.status_code = utl_http.http_ok
    then
      l_error_description := null;
    elsif l_res.status_code = 503
    then
      l_error_description := 'AOP Server not running or can not be reached.';
    elsif l_res.status_code = 500
    then
      for i in 1 .. sys.utl_http.get_header_count(l_res) loop
        sys.utl_http.get_header(l_res, i, l_head_name, l_head_value);
        if l_head_name = 'error_description'
        then
          l_error_description := l_head_value;
          -- errors returned by AOP server are base64 encoded
          l_error_description := utl_encode.text_decode(l_error_description, 'AL32UTF8', utl_encode.base64);
        end if;
      end loop;
    else
      l_error_description := 'Unknown error. Check AOP server logs.';
    end if;

    if l_error_description is not null
    then
      raise_application_error(-20002, 'Issue returned by AOP Service (REST call: ' || l_res.status_code || '): ' || CHR(10) || l_error_description);

    else
      -- body
      sys.dbms_lob.createtemporary (lob_loc => l_blob, cache => true );
      begin
        loop
          sys.utl_http.read_raw(l_res, l_raw_buf);
          sys.dbms_lob.writeappend( l_blob, sys.utl_raw.length(l_raw_buf), l_raw_buf );
        end loop;
      exception
      when others
      then
        null; -- end reading output
      end;
      sys.utl_http.end_response(l_res);
    end if;

  end if;

  -- return print
  return l_blob;

end make_aop_request;

end aop_plsql_only_pkg;
/
