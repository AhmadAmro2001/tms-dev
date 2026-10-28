
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."AOP_PLSQL25_PKG"
AUTHID CURRENT_USER
as

/* Copyright 2015-2025 - APEX RnD - United Codes
*/

/* AOP Version */
c_aop_version  constant varchar2(6)   := '25.1.2';

--
-- Pre-requisites: apex_web_service package
-- if APEX is not installed, you can use this package as your starting point
-- but you would need to change the apex_web_service calls by utl_http calls or similar
--


--
-- Change following variables for your environment
--
g_aop_url  varchar2(200) := 'http://api.apexofficeprint.com/';                  -- for https use https://api.apexofficeprint.com/
g_api_key  varchar2(200) := '';    -- change to your API key in APEX 18 or above you can use apex_app_setting.get_value('AOP_API_KEY')
g_aop_mode varchar2(15)  := null;  -- AOP Mode can be development or production; when running in development no cloud credits are used but a watermark is printed

-- Global variables
-- Call to AOP
g_proxy_override          varchar2(300) := null;  -- null=proxy defined in the application attributes
g_transfer_timeout        number(6)     := 180;   -- default is 180
g_wallet_path             varchar2(300) := null;  -- null=defined in Manage Instance > Instance Settings
g_wallet_pwd              varchar2(300) := null;  -- null=defined in Manage Instance > Instance Settings

-- Output parameters
--### Output
g_output_directory          varchar2(200) := '.';   -- set output directory on AOP Server, if . is specified the files are saved in the default directory: outputfiles
g_output_sign_certificate   varchar2(32000) := null;-- sign PDF with signature which is base64 encoded
g_output_split              varchar2(5)   := null;  -- split file: one file per page: true/false
g_output_merge              varchar2(5)   := null;  -- merge files into one PDF true/false
g_output_icon_font          varchar2(20)  := null;  -- the icon font to use for the output, Font-APEX or Font Awesome 5 (default)
g_output_even_page          varchar2(5)   := null;  -- PDF option to always print even pages (necessary for two-sided pages): true/false
g_output_merge_making_even  varchar2(5)   := null;  -- PDF option to merge making all documents even paged (necessary for two-sided pages): true/false
g_output_page_margin        varchar2(50)  := null;  -- HTML to PDF option: margin in px, can also add top, bottom, left, right
g_output_page_orientation   varchar2(10)  := null;  -- HTML to PDF option: portrait (default) or landscape
g_output_page_width         varchar2(10)  := null;  -- HTML to PDF option: width in px, mm, cm, in. No unit means px.
g_output_page_height        varchar2(10)  := null;  -- HTML to PDF option: height in px, mm, cm, in. No unit means px.
g_output_page_format        varchar2(10)  := null;  -- HTML to PDF option: a4 (default), letter
g_output_remove_last_page   boolean       := false; -- PDF option to remove the last page; e.g. when the last page is empty
--### PDF
g_output_read_password      varchar2(200) := null;  -- protect PDF to read
g_output_modify_password    varchar2(200) := null;  -- protect PDF to write (modify)
g_output_pwd_protection_flag number(4)    := null;  -- optional; default is 4.
                                                    -- Number when bit calculation is done as specified in http://pdfhummus.com/post/147451287581/hummus-1058-and-pdf-writer-updates-encryption
g_output_correct_page_nr    boolean        := false;-- boolean to check for AOPMergePage text to replace it with the page number.
g_output_lock_form          boolean        := false;-- boolean that determines if the pdf forms should be locked/flattened.
g_identify_form_fields      boolean        := false;-- boolean that fills in the name of the fields of a PDF Form in the field itself so it's easy to identify which field is at what position
g_output_watermark          varchar2(4000) := null; -- Watermark in PDF
g_output_watermark_color    varchar2(500)  := null; -- Watermark option color
g_output_watermark_font     varchar2(500)  := null; -- Watermark option font
g_output_watermark_width    varchar2(500)  := null; -- Watermark option width
g_output_watermark_height   varchar2(500)  := null; -- Watermark option height
g_output_watermark_opacity  varchar2(500)  := null; -- Watermark option opacity
g_output_watermark_rotation varchar2(500)  := null; -- Watermark option rotation
g_output_copies             number         := null; -- Requires output pdf, repeats the output pdf for the given number of times.
g_output_insert_barcode     boolean        := false; -- boolean to insert barcode in PDF, default is false

--### CSV
g_output_text_delimiter     varchar2(200) := null;  --
g_output_field_separator    varchar2(200) := null;  --
g_output_character_set      varchar2(200) := null;  --

-- Constants
c_mime_type_docx        constant varchar2(100) := 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
c_mime_type_xlsx        constant varchar2(100) := 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
c_mime_type_pptx        constant varchar2(100) := 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
c_mime_type_pdf         constant varchar2(100) := 'application/pdf';
c_mime_type_html        constant varchar2(9)   := 'text/html';
c_mime_type_markdown    constant varchar2(13)  := 'text/markdown';


function make_aop_request(
  p_aop_url            in varchar2 default g_aop_url,
  p_api_key            in varchar2 default g_api_key,
  p_aop_mode           in varchar2 default g_aop_mode,
  p_json               in clob,
  p_template           in blob,
  p_template_type      in varchar2 default null,
  p_output_encoding    in varchar2 default 'raw', -- change to raw to have binary, change to base64 to have base64 encoded
  p_output_type        in varchar2 default null,
  p_output_filename    in varchar2 default 'output',
  p_aop_remote_debug   in varchar2 default 'No',
  p_output_converter   in varchar2 default '',
  p_prepend_files_json in clob default null,
  p_append_files_json  in clob default null,
  p_templates_json     in clob default null
  )
  return blob;

end aop_plsql25_pkg;
/
