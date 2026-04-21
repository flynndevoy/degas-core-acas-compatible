# DAAEncounterVerticalOnly

This folder provides a vertical-only ACAS example built on top of the standard `DAAEncounter` model.

What it does:
- uses the normal ACAS DEGAS backend
- loads the Section 3 vertical policy CSV from `acas-vertical`
- forces horizontal ACAS actions to `COC` in the backend
- enables only vertical maneuvers in the simulation (`enableVertMan = 1`, `enableHorzMan = 0`)
- uses the same encounter file flow as `RUN_ACAS` / `RUN_DAIDALUS`
- strips only the nominal horizontal scripted turn/accel content from the selected encounter before simulation

Main entry point:
- `RUN_ACAS_VERTICAL_ONLY.m`
