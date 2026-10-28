
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."AOP_PLSQL_ONLY_PKG"
authid current_user
as

/* Copyright 2015-2025 - APEX RnD - United Codes
*/

/* AOP Version */
c_aop_version  constant varchar2(6)   := '25.1.2';

--
-- PL/SQL only version, not needing Oracle APEX. Requests are being done by UTL_HTTP
--

--
-- Change following variables for your environment
--
g_aop_url  varchar2(200) := 'https://api.apexofficeprint.com/'; -- for http use http://api.apexofficeprint.com/
g_api_key  varchar2(200) := '';    -- change to your API key
g_aop_mode varchar2(15)  := null;  -- AOP Mode can be development or production; when running in development no cloud credits are used but a watermark is printed

g_wallet_path varchar2(300 char) := null; -- specify for an HTTPS call
g_wallet_pwd  varchar2(300 char) := null; -- specify for an HTTPS call

g_output_converter varchar2(250) := null;


-- Constants
c_mime_type_docx        constant varchar2(100) := 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
c_mime_type_xlsx        constant varchar2(100) := 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
c_mime_type_pptx        constant varchar2(100) := 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
c_mime_type_pdf         constant varchar2(100) := 'application/pdf';
c_mime_type_html        constant varchar2(9)   := 'text/html';
c_mime_type_markdown    constant varchar2(13)  := 'text/markdown';


-- Helper functions
function replace_with_clob(
   p_source in clob
  ,p_search in varchar2
  ,p_replace in clob
) return clob;

function blob2clobbase64(p_blob in blob)
return clob;


/**
 * @Description: Make a call to the AOP Server and generate the correct JSON with PL/SQL.
 *
 * @Author: Dimitri Gielis
 * @Created: 29/7/2023
 *
 * @Param: p_aop_url  URL of AOP Server
 * @Param: p_api_key  API Key in case AOP Cloud is used
 * @Param: p_aop_mode  API Key in case AOP Cloud is used
 * @Param: p_data_json  Data in JSON format
 * @Param: p_template  Template in blob format
 * @Param: p_template_type  The type of the template e.g. docx, xlsx, pptx, html, txt, md
 * @Param: p_output_type  The extension of the output e.g. pdf, if no output type is defined, the same extension as the template is used
 * @Param: p_output_filename  Filename of the result
 * @Param: p_aop_debug  Ability to do local (or remote debugging in case the AOP Cloud is used)
 * @Param: p_prepend_files_json Prepend files
 * @Param: p_append_files_json Append Files
 * @Param: p_templates_json Use Sub-templates
 * @Param: p_output_json Configure extra output parameters e.g. output_page_height, output_page_format, output_page_number_start_at, output_remove_last_page
 * @Return: Resulting file where the template and data are merged and outputted in the requested format (output type).
 * @Example:

-- Generate an AOP Template in Word based on the data I provide
declare
  l_blob blob;
begin
  l_blob := aop_plsql_only_pkg.make_aop_request(
              p_aop_url   => 'https://api.apexofficeprint.com/',
              p_api_key   => '',
              p_data_json => q'!
                                [
                                  {
                                    "filename": "file1",
                                    "data": [
                                        {
                                          "cust_city": "St. Louis",
                                          "cust_first_name": "Albertos",
                                          "cust_last_name": "Lambert",
                                          "orders": [
                                              {
                                                "order_name": "Order 1",
                                                "order_total": 950,
                                                "product": [
                                                    {
                                                        "product_name": "Business \nShirt",
                                                        "quantity": 3,
                                                        "unit_price": 50
                                                    },
                                                    {
                                                        "product_name": "Trousers",
                                                        "quantity": 2,
                                                        "unit_price": 80
                                                    }
                                                ]
                                              }
                                          ]
                                        }
                                    ]
                                  }
                                ]
              !',
              p_output_type => 'docx'
            );

  insert into aop_output (output_blob, filename, mime_type, last_update_date)
  values (l_blob, 'plsql_only_doc.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', sysdate);
end;

-- Generate PDF based on Word template
declare
  l_template blob;
  l_pdf      blob;
begin
  select template_blob
    into l_template
    from aop_template
   where id = 1;

  l_pdf := aop_plsql_only_pkg.make_aop_request(
              p_aop_url   => 'https://api.apexofficeprint.com/',
              p_api_key   => '',
              p_template_type => 'docx',
              p_template  => l_template,
              p_data_json => q'!
                                [
                                  {
                                    "filename": "file1",
                                    "data": [
                                        {
                                          "cust_city": "St. Louis",
                                          "cust_first_name": "Albertos",
                                          "cust_last_name": "Lambert"
                                        }
                                    ]
                                  }
                                ]
              !',
              p_output_type => 'pdf'
            );

  insert into aop_output (output_blob, filename, mime_type, last_update_date)
  values (l_pdf, 'plsql_only_pdf.pdf', 'application/pdf', sysdate);
end;
 *
 */
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
  return blob;

end aop_plsql_only_pkg;
/
