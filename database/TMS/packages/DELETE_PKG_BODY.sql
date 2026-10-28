
  CREATE OR REPLACE EDITIONABLE PACKAGE BODY "TMS"."DELETE_PKG" as
    procedure delete_department(
    p_id in number
    ) is
begin
    delete from department
    where id = p_id;
end delete_department;

procedure delete_project(
    p_id in number
    ) is
begin
    delete from PROJECT
    where id = p_id;
end delete_project;


procedure delete_permission(
    p_id in number
    ) is
begin
    delete from PERMISSION
    where id = p_id;
end delete_permission;


procedure delete_special_leaves(
    p_id in number
    ) is
begin
    delete from SPECIAL_LEAVE
    where id = p_id;
end delete_special_leaves;

procedure delete_approved_time(
    p_id in number
    ) is
begin
    delete from APPROVED_OVERTIME
    where id = p_id;
end delete_approved_time;

procedure delete_shift(
    p_id in number
    ) is
begin
    delete from SHIFT
    where id = p_id;
end delete_shift;


procedure delete_public_holiday(
    p_id in number
    ) is
begin
    delete from OFFICIAL_HOLIDAY
    where id = p_id;
end delete_public_holiday;


procedure delete_location(
    p_id in number
    ) is
begin
    delete from location
    where id = p_id;
end delete_location;


procedure delete_vacation(
    p_id in number
    ) is
begin
    delete from vacation
    where id = p_id;
end delete_vacation;

procedure delete_mission(
    p_id in number
    ) is
begin
    delete from MISSION
    where id = p_id;
end delete_mission;


procedure delete_training(
    p_id in number
    ) is
begin
    delete from TRAINING
    where id = p_id;
end delete_training;

procedure delete_plan(
    p_id in number
    ) is
begin
    delete from rotation_plan
    where id = p_id;
end delete_plan;

end "DELETE_PKG";
/
