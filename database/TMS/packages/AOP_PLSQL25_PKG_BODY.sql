
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."AOP_PLSQL25_PKG" as

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


/**
 * @Description: Example how to make a manual call to the AOP Server and generate the correct JSON.
 *
 * @Author: Dimitri Gielis
 * @Created: 9/1/2018
 *
 * @Param: p_aop_url URL of AOP Server
 * @Param: p_api_key API Key in case AOP Cloud is used
 * @Param: p_json Data in JSON format
 * @Param: p_template Template in blob format
 * @Param: p_template_type The type of the template e.g. docx, xlsx, pptx, html, txt, md
 * @Param: p_output_encoding Encoding in raw or base64
 * @Param: p_output_type The extension of the output e.g. pdf, if no output type is defined, the same extension as the template is used
 * @Param: p_output_filename Filename of the result
 * @Param: p_aop_remote_debug Ability to do remote debugging in case the AOP Cloud is used
 * @Param: p_output_converter
 * @Param: p_prepend_files_json
 * @Param: p_append_files_json
 * @Param: p_templates_json
 * @Param: p_render_pdf_barcode Boolean to render a barcode in the PDF
 * @Return: Resulting file where the template and data are merged and outputted in the requested format (output type).
 */
function make_aop_request(
  p_aop_url            in varchar2 default g_aop_url,
  p_api_key            in varchar2 default g_api_key,
  p_aop_mode           in varchar2 default g_aop_mode,
  p_json               in clob,
  p_template           in blob,
  p_template_type      in varchar2 default null,
  p_output_encoding    in varchar2 default 'raw',
  p_output_type        in varchar2 default null,
  p_output_filename    in varchar2 default 'output',
  p_aop_remote_debug   in varchar2 default 'No',
  p_output_converter   in varchar2 default '',
  p_prepend_files_json in clob default null,
  p_append_files_json  in clob default null,
  p_templates_json     in clob default null)
  return blob
as
  l_aop_json          clob;
  l_template_clob     clob;
  l_template_type     varchar2(10);
  l_data_json         clob;
  l_output_type       varchar2(10);
  l_blob              blob;
  l_error_description varchar2(32767);
  l_amount                   integer := dbms_lob.lobmaxsize;
  l_dest_offset              integer := 1 ;
  l_src_offset               integer := 1 ;
  l_blob_csid                integer := dbms_lob.default_csid;
  l_lang_context             integer := dbms_lob.default_lang_ctx;
  l_warning                  integer := dbms_lob.warn_inconvertible_char;
begin
  l_template_clob := apex_web_service.blob2clobbase64(p_template);
  l_template_clob := replace(l_template_clob, chr(13) || chr(10), null);
  l_template_clob := replace(l_template_clob, '"', '\u0022');

  if p_template_type is null
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
      l_template_type := 'unknown';
    end if;
  else
      l_template_type := p_template_type;
  end if;

  if p_output_type is null
  then
    l_output_type := l_template_type;
  else
    l_output_type := p_output_type;
  end if;

  l_data_json := p_json;

  l_aop_json := '
  {
      "version": "***AOP_VERSION***",
      "api_key": "***AOP_API_KEY***",
      "mode": "***AOP_MODE***",
      "aop_remote_debug": "***AOP_REMOTE_DEBUG***",
      "template": {
        "file":"***AOP_TEMPLATE_BASE64***",
         "template_type": "***AOP_TEMPLATE_TYPE***"
      },
      "templates":
        ***AOP_TEMPLATES_JSON***,
      "output": {
        "output_encoding": "***AOP_OUTPUT_ENCODING***",
        "output_type": "***AOP_OUTPUT_TYPE***",
        "output_converter": "***AOP_OUTPUT_CONVERTER***",
        "icon_font": "g_output_icon_font",
        "output_watermark": "g_output_watermark",
        "output_watermark_color": "g_output_watermark_color",
        "output_watermark_font": "g_output_watermark_font",
        "output_watermark_width": "g_output_watermark_width",
        "output_watermark_height": "g_output_watermark_height",
        "output_watermark_opacity": "g_output_watermark_opacity",
        "output_watermark_rotation": "g_output_watermark_rotation",
        "output_modify_password": "g_output_modify_password",
        "output_read_password": "g_output_read_password",
        "output_password_protection_flag": "g_output_pwd_protection_flag",
        "output_correct_page_number": g_output_correct_page_nr,
        "lock_form": g_output_lock_form,
        "identify_form_fields": g_identify_form_fields,
        "output_even_page": "g_output_even_page",
        "output_merge_making_even": "g_output_merge_making_even",
        "output_split": "g_output_split",
        "output_merge": "g_output_merge",
        "output_sign_certificate": "g_output_sign_certificate",
        "output_copies": "g_output_copies",
        "output_page_margin": "g_output_page_margin",
        "output_page_orientation": "g_output_page_orientation",
        "output_page_width": "g_output_page_width",
        "output_page_height": "g_output_page_height",
        "output_page_format": "g_output_page_format",
        "output_text_delimiter": "g_output_text_delimiter",
        "output_field_separator": "g_output_field_separator",
        "output_character_set": "g_output_character_set",
        "output_remove_last_page": "g_output_remove_last_page",
        "output_insert_barcode": "g_output_insert_barcode"
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
  l_aop_json := replace(l_aop_json, '***AOP_REMOTE_DEBUG***', p_aop_remote_debug);
  l_aop_json := replace_with_clob(l_aop_json, '***AOP_TEMPLATE_BASE64***', l_template_clob);
  l_aop_json := replace_with_clob(l_aop_json, '***AOP_TEMPLATE_TYPE***', l_template_type);
  l_aop_json := replace(l_aop_json, '***AOP_OUTPUT_ENCODING***', p_output_encoding);
  l_aop_json := replace(l_aop_json, '***AOP_OUTPUT_TYPE***', l_output_type);
  l_aop_json := replace(l_aop_json, '***AOP_OUTPUT_CONVERTER***', p_output_converter);
  l_aop_json := replace_with_clob(l_aop_json, '***AOP_DATA_JSON***', l_data_json);
  l_aop_json := replace_with_clob(l_aop_json, '***AOP_PREPEND_FILES_JSON***', nvl(p_prepend_files_json,'[]'));
  l_aop_json := replace_with_clob(l_aop_json, '***AOP_APPEND_FILES_JSON***', nvl(p_append_files_json,'[]'));
  l_aop_json := replace_with_clob(l_aop_json, '***AOP_TEMPLATES_JSON***', nvl(p_templates_json,'[]'));
  l_aop_json := replace(l_aop_json, 'g_output_icon_font', g_output_icon_font);
  l_aop_json := replace(l_aop_json, 'g_output_watermark_color', g_output_watermark_color);
  l_aop_json := replace(l_aop_json, 'g_output_watermark_font', g_output_watermark_font);
  l_aop_json := replace(l_aop_json, 'g_output_watermark_width', g_output_watermark_width);
  l_aop_json := replace(l_aop_json, 'g_output_watermark_height', g_output_watermark_height);
  l_aop_json := replace(l_aop_json, 'g_output_watermark_opacity', g_output_watermark_opacity);
  l_aop_json := replace(l_aop_json, 'g_output_watermark_rotation', g_output_watermark_rotation);
  l_aop_json := replace(l_aop_json, 'g_output_watermark', g_output_watermark);
  l_aop_json := replace(l_aop_json, 'g_output_modify_password', g_output_modify_password);
  l_aop_json := replace(l_aop_json, 'g_output_read_password', g_output_read_password);
  l_aop_json := replace(l_aop_json, 'g_output_pwd_protection_flag', to_char(g_output_pwd_protection_flag));
  l_aop_json := replace(l_aop_json, 'g_output_correct_page_nr', case when g_output_correct_page_nr then 'true' else 'false' end);
  l_aop_json := replace(l_aop_json, 'g_output_lock_form', case when g_output_lock_form then 'true' else 'false' end);
  l_aop_json := replace(l_aop_json, 'g_identify_form_fields', case when g_identify_form_fields then 'true' else 'false' end);
  l_aop_json := replace(l_aop_json, 'g_output_even_page', g_output_even_page);
  l_aop_json := replace(l_aop_json, 'g_output_merge_making_even', g_output_merge_making_even);
  l_aop_json := replace(l_aop_json, 'g_output_split', g_output_split);
  l_aop_json := replace(l_aop_json, 'g_output_merge', g_output_merge);
  l_aop_json := replace(l_aop_json, 'g_output_sign_certificate', g_output_sign_certificate);
  l_aop_json := replace(l_aop_json, 'g_output_copies', to_char(g_output_copies));
  l_aop_json := replace(l_aop_json, 'g_output_page_margin', g_output_page_margin);
  l_aop_json := replace(l_aop_json, 'g_output_page_orientation', g_output_page_orientation);
  l_aop_json := replace(l_aop_json, 'g_output_page_width', g_output_page_width);
  l_aop_json := replace(l_aop_json, 'g_output_page_height', g_output_page_height);
  l_aop_json := replace(l_aop_json, 'g_output_page_format', g_output_page_format);
  l_aop_json := replace(l_aop_json, 'g_output_text_delimiter', g_output_text_delimiter);
  l_aop_json := replace(l_aop_json, 'g_output_field_separator', g_output_field_separator);
  l_aop_json := replace(l_aop_json, 'g_output_character_set', g_output_character_set);
  l_aop_json := replace(l_aop_json, '"g_output_insert_barcode"', case when g_output_insert_barcode then 'true' else 'false' end );
  l_aop_json := replace(l_aop_json, 'g_output_remove_last_page', case when g_output_remove_last_page then 'true' else 'false' end);
  l_aop_json := replace(l_aop_json, '\\n', '\n');

  --logger.log(p_text  => 'AOP JSON: ' || p_message, p_scope => 'AOP', p_extra => l_aop_json);

  if p_aop_remote_debug = 'Local'
  then
    dbms_lob.createtemporary(l_blob, false);
    dbms_lob.converttoblob (
        dest_lob    => l_blob,
        src_clob    => l_aop_json,
        amount      => l_amount,
        dest_offset => l_dest_offset,
        src_offset  => l_src_offset,
        blob_csid   => l_blob_csid,
        lang_context=> l_lang_context,
        warning     => l_warning
    );
  else
    apex_web_service.g_request_headers.delete;
    apex_web_service.g_request_headers(1).name := 'Content-Type';
    apex_web_service.g_request_headers(1).value := 'application/json';

    begin
      l_blob := apex_web_service.make_rest_request_b(
        p_url              => p_aop_url,
        p_http_method      => 'POST',
        p_body             => l_aop_json,
        p_proxy_override   => g_proxy_override,
        p_transfer_timeout => g_transfer_timeout,
        p_wallet_path      => g_wallet_path,
        p_wallet_pwd       => g_wallet_pwd);
    exception
    when others
    then
      raise_application_error(-20001,'Issue calling AOP Service (REST call: ' || apex_web_service.g_status_code || '): ' || CHR(10) || SQLERRM);
    end;

    -- read header variable and create error message
    -- HTTP Status Codes:
    --  200 is normal
    --  500 error received
    --  503 Service Temporarily Unavailable, the AOP server is probably not running
    if apex_web_service.g_status_code = 200
    then
      l_error_description := null;
    elsif apex_web_service.g_status_code = 503
    then
      l_error_description := 'AOP Server not running.';
    elsif apex_web_service.g_status_code = 500
    then
      for l_loop in 1.. apex_web_service.g_headers.count loop
        if apex_web_service.g_headers(l_loop).name = 'error_description'
        then
          l_error_description := apex_web_service.g_headers(l_loop).value;
          -- errors returned by AOP server are base64 encoded
          l_error_description := utl_encode.text_decode(l_error_description, 'AL32UTF8', UTL_ENCODE.BASE64);
        end if;
      end loop;
    else
      l_error_description := 'Unknown error. Check AOP server logs.';
    end if;

    -- YOU CAN STORE THE L_BLOB TO A LOCAL DEBUG TABLE AS AOP SERVER RETURNS A DOCUMENT WITH MORE INFORMATION
    --

    -- check if succesfull
    if apex_web_service.g_status_code <> 200
    then
      raise_application_error(-20002,'Issue returned by AOP Service (REST call: ' || apex_web_service.g_status_code || '): ' || CHR(10) || l_error_description);
    end if;
  end if;

  -- return print
  return l_blob;

end make_aop_request;

end aop_plsql25_pkg;
/
