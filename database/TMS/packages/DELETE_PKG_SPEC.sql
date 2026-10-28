
  CREATE OR REPLACE EDITIONABLE PACKAGE "TMS"."DELETE_PKG" as

    procedure delete_department(
    p_id in number
);

    procedure delete_project(
    p_id in number
);

    procedure delete_permission(
    p_id in number
);

    procedure delete_special_leaves(
    p_id in number
);

    procedure delete_approved_time(
    p_id in number
);

    procedure delete_shift(
    p_id in number
);

    procedure delete_public_holiday(
    p_id in number
);

    procedure delete_location(
    p_id in number
);
    procedure delete_vacation(
    p_id in number
);

    procedure delete_mission(
    p_id in number
);
   procedure delete_training(
    p_id in number
);

   procedure delete_plan(
    p_id in number
);
end "DELETE_PKG";
/
