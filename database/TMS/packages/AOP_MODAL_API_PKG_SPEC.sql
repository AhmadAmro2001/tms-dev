
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."AOP_MODAL_API_PKG"
as

/* Copyright 2015-2025 - APEX RnD - United Codes
*/

  procedure subscribe_to_report(
    p_app_id                    in aop_downsubscr.app_id%type,
    p_page_id                   in aop_downsubscr.page_id%type,
    p_region_pipe_report_ids    in aop_downsubscr.region_pipe_report_ids%type, -- format: region_id|report_id
    p_items_in_session          in aop_downsubscr.items_in_session%type,       -- format: P1_X,P1_Y
    p_app_user                  in aop_downsubscr.app_user%type,
    p_report_format             in aop_downsubscr.output_type%type,
    p_template_sql              in aop_downsubscr.template_source%type,
    p_output_to                 in aop_downsubscr.output_to%type,
    p_output_procedure          in aop_downsubscr.output_procedure%type,
    p_email_from                in aop_downsubscr.email_from%type,
    p_email_to                  in aop_downsubscr.email_to%type,
    p_email_cc                  in aop_downsubscr.email_cc%type,
    p_email_bcc                 in aop_downsubscr.email_bcc%type,
    p_email_download_link       in varchar2,
    p_email_blob_size           in varchar2,
    p_save_log                  in varchar2,
    p_subject                   in aop_downsubscr.email_subject%type,
    p_body_text                 in aop_downsubscr.email_body_text%type,
    p_body_html                 in aop_downsubscr.email_body_html%type,
    p_when                      in varchar2,  -- now or scheduled
    p_start_date                in aop_downsubscr.start_date%type,
    p_end_date                  in aop_downsubscr.end_date%type,
    p_repeat_every              in aop_downsubscr.repeat_every%type,
    p_repeat_interval           in aop_downsubscr.repeat_interval%type,
    p_repeat_days               in aop_downsubscr.repeat_days%type,
    p_init_code                 in aop_downsubscr.init_code%type,
    po_downsubscr_output_id     out aop_downsubscr_output.id%type,
    po_output_blob              out aop_downsubscr_output.output_blob%type,
    po_output_filename          out aop_downsubscr_output.output_filename%type,
    po_output_mime_type         out aop_downsubscr_output.output_mime_type%type,
    po_job_name                 out aop_downsubscr.job_name%type
  );
  procedure run_scheduled_report(
    p_downsubscr_id in aop_downsubscr.id%type);

-- To force immediate job execution
procedure execute_job (
  p_job_name in user_scheduler_jobs.job_name%type);

-- Remove job from scheduler by name
procedure remove_job (
  p_job_name in user_scheduler_jobs.job_name%type) ;

-- Indicates whether the job is enabled (TRUE) or not (FALSE)
function is_job_enabled (
  p_job_name in user_scheduler_jobs.job_name%type)
return boolean;

-- Enable job from scheduler by name
procedure enable_job (
  p_job_name in user_scheduler_jobs.job_name%type);

-- Disable job from scheduler by name
procedure disable_job (
  p_job_name in user_scheduler_jobs.job_name%type);

end aop_modal_api_pkg;
/
