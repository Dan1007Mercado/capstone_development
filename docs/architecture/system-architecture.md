# capstone_Development System Architecture

## Purpose

This repository develops the core engines that will later be integrated into the complete TalaanScan application.

The immediate focus is reliable OMR processing rather than UI.

## Core Data Flow

TemplateDefinition
→ validation
→ LayoutEngine
→ PageLayout

PageLayout branches into:

1. PDF generation
2. OMR recognition

This shared geometry ensures the printed form and scanner use identical coordinates.

## Engine Layers

Template Engine

Layout Engine

PDF Engine

Camera Engine

ArUco Engine

Preprocessing Engine

Recognition Engine

Scanner Engine

Testing/Diagnostics

## External Systems

Firebase and final application integration are intentionally secondary during engine development.

Core engine behavior must remain testable offline.

## Initial Constraints

- Android-first scanner
- A4 first
- deterministic recognition
- four ArUco markers
- no ML
- offline recognition
- minimal test UI
- multi-page-capable architecture
