# Project: TMS (Time Management System)

<!-- Project overview for this team. The template upgrade never overwrites this file. -->

## Overview
**TMS** is an enterprise Oracle APEX application (Application ID `301`, parsing schema `TMS`) for workforce time and attendance management, biometric punch ingestion, shift scheduling, exception/leave tracking, and automated monthly timesheet generation.

## Key Capabilities
- **Biometric Punch & Device Management**: Tracks network-connected attendance devices, pulls transaction logs into staging, matches punches against employee badges, and audits unmatched punches.
- **Organization & Employee Hierarchy**: Manages employees, departments, projects, physical work locations, and grades.
- **Shift Scheduling & Rotations**: Configures shifts (work hours, grace periods, breaks), multi-day rotation plans, alternate shift assignments, public holidays, and monthly payroll cut-off dates.
- **Absences & Exceptions**: Tracks vacations, official business missions, training sessions, hourly permissions, special leaves, and pre-approved overtime.
- **Timesheet Processing Engine**: Calculates daily and monthly attendance metrics (work hours, overtime, late arrivals, early departures, unauthorized absences) with caching in `TIME_SHEET_CACHE`.
- **Reporting & Office Print**: Comprehensive operational dashboards, monthly employee timesheets, and export capabilities integrated with APEX Office Print (AOP).
- **Security & Multi-Tenant Location Scoping**: Custom authentication (`AUTH_PKG`), feature-level permissions, and row-level location scoping restricting managers to permitted physical sites.

## Core Schema & Components
- **Database Schema**: `TMS` (60 tables, 12 views, 20 PL/SQL packages, 9 triggers).
- **APEX Application**: ID `301` under workspace `EPROMHQ`.
- **Primary Packages**:
  - `AUTH_PKG`: Authentication, feature gating, role checking, and location-based scoping.
  - `TRANSACTION_API_PKG`: Punch ingestion, manual punch adjustments, device sync.
  - `TIMESHEET_API_PKG`: Timesheet summaries, daily status, incomplete hours.
  - `TIME_SHEET_REPORT_PKG`: High-performance timesheet reporting and monthly cache population.
  - `SCHEDULE_API_PKG`: Shifts, rotation plans, alternate shifts, cut dates, holidays.
  - `DEVICE_API_PKG`: Device registry, command queuing, status tracking.
  - `EVENT_API_PKG`: Vacations, missions, trainings, permissions, overtime.
