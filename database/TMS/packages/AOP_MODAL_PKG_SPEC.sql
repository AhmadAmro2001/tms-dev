
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."AOP_MODAL_PKG" as

  /**
  * @project:
  *   United Codes APEX Office Print
  *
  * @description:
  *   The package contains the plug-in PL/SQL code implementing dynamic action plug-in
  *
  * @author:
  *  Bartosz Ostrowski
  *
  * @created:
  *   Dimitri Gielis
  *
  * United Codes
  * Copyright (C) 2015-2024 by United Codes
  *
  * Changelog:
  *
  *   v21.2   2021-10-05 - form elements can be validated using the plug-in attribute Initialization JavaScript Code
  *                        function( pOptions ) {
  *                          pOptions.validation.scheduleDateStart = function( pStartDateValue, pStartDateVisible, pEndDateValue, pEndDateVisible ) {
  *                            if ( 1 == 1 ) {
  *                              //validation failed
  *                              return 'Custom validation message';
  *                            }
  *                            //validation passed
  *                            return null;
  *                          };
  *
  *                          pOptions.validation.emailTo = function( pValue ) {
  *                            if ( 1 == 1 ) {
  *                              //validation failed
  *                              return 'Custom validation message';
  *                            }
  *
  *                            //validation passed
  *                            return null;
  *                          };
  *
  *                          return pOptions;
  *                        }
  *                      - date start and date end has built in validation checking if start date is before the date end
  *
  *   v21.1.3 2021-09-14 - email from can be now specified using the plug-in attribute Initialization JavaScript Code
  *                        example code:
  *                        function( pOptions ){
  *                          //pOptions.emailFrom = "ostrowski.bartosz@gmail.com"; // static assigment
  *                          //pOptions.emailFrom = apex.item('PX_ITEM_NAME');     // current value of a given APEX item
  *                          return pOptions;
  *                        }
  *
  */

  g_template_id_arr      apex_t_varchar2;
  g_template_name_arr    apex_t_varchar2;
  g_template_default_arr apex_t_varchar2;
  g_template_type_arr    apex_t_varchar2;
  g_mime_type_arr        apex_t_varchar2;

  g_default_cnt_arr      apex_t_number;
  g_blob                 blob;


  function render(
    p_dynamic_action in apex_plugin.t_dynamic_action,
    p_plugin         in apex_plugin.t_plugin
  ) return apex_plugin.t_dynamic_action_render_result;

  function ajax(
    p_dynamic_action in apex_plugin.t_dynamic_action,
    p_plugin         in apex_plugin.t_plugin
  ) return apex_plugin.t_dynamic_action_ajax_result;

end aop_modal_pkg;
/
