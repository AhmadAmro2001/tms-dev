
  CREATE OR REPLACE EDITIONABLE PROCEDURE "TMS"."AOP_OUTPUTTO_EMAIL" (
  p_output_blob      in blob,
  p_output_filename  in varchar2,
  p_output_mime_type in varchar2
) is
  l_mail_id              number;
  l_downsubscr_output_id aop_downsubscr_output.id%type;
  l_email_body_text      varchar2(4000);
begin
  -- the AOP Plug-in will store the email form in the AOP_OUTPUTTO collection
  for r in (select
              c001 as app_id,
              c002 as page_id,
              c003 as region_pipe_report_ids,
              c004 as app_user,
              c005 as template_type,
              c006 as template_source,
              c007 as output_type,
              c008 as output_to,
              c009 as output_procedure,
              c010 as email_from,
              c011 as email_to,
              c012 as email_cc,
              c013 as email_bcc,
              c014 as email_subject,
              c015 as email_body_text,
              c016 as email_body_html,
              c017 as email_download_link,
              c018 as email_blob_size,
              c019 as save_log,
              c020 as downsubscr_id
              from apex_collections
             where collection_name = 'AOP_OUTPUTTO')
  loop
    -- loop will happen only 1 time, for ease of coding used a for loop

    -- for small files, send directly with email
    if dbms_lob.getlength(p_output_blob) < 500000
    then
      l_mail_id := apex_mail.send(
                      p_from  => r.email_from,
                      p_to    => r.email_to,
                      p_cc    => r.email_cc,
                      p_bcc   => r.email_bcc,
                      p_subj  => r.email_subject,
                      p_body  => r.email_body_text
                  );

      -- we send the document as attachment
      apex_mail.add_attachment(
          p_mail_id    => l_mail_id,
          p_attachment => p_output_blob,
          p_filename   => p_output_filename,
          p_mime_type  => p_output_mime_type);

    else
      -- for large files, we will send a link to the document.
      insert into aop_downsubscr_output(
        downsubscr_id,
        output_filename,
        output_blob,
        output_mime_type
      ) values(
        r.downsubscr_id,
        p_output_filename,
        p_output_blob,
        p_output_mime_type
      ) returning id into l_downsubscr_output_id;

      if instr(r.email_body_text,'#DOWNLOAD_LINK#')>0
      then
          l_email_body_text := replace(r.email_body_text, '#DOWNLOAD_LINK#', r.email_download_link||'&aop_downsubscr_output_id=' || l_downsubscr_output_id);
      else
          l_email_body_text := r.email_body_text || CHR(10) || ' <br/>As the file was too big, click to <a href="' || r.email_download_link||'&aop_downsubscr_output_id=' || l_downsubscr_output_id || '">download the file</a>.';
      end if;

      l_mail_id := apex_mail.send(
                          p_from => r.email_from,
                          p_to   => r.email_to,
                          p_cc   => r.email_cc,
                          p_bcc  => r.email_bcc,
                          p_subj => r.email_subject,
                          p_body => l_email_body_text);
      -- no attachment
    end if;

  end loop;

  -- push queue
  apex_mail.push_queue;

end aop_outputto_email;
/
