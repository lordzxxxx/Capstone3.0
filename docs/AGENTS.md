AGENTS.md

Purpose

This repository contains a health information system used by different user roles, including CHO and BHW workflows, with web and Flutter/mobile interfaces.

This file defines the engineering rules that Codex and other coding agents must follow when working in this repository.

The primary objectives are:

keep the system reliable and functional;

preserve existing working business logic;

maintain clear separation between CHO and BHW permissions;

keep web and mobile behavior consistent;

improve maintainability without unnecessary rewrites;

protect data integrity;

improve AI behavior through measurable evaluation;

improve OCR through measurable field-level accuracy;

preserve offline functionality and synchronization;

maintain strong UI/UX consistency;

avoid introducing regressions.

Before changing code, inspect the real implementation. Do not assume that a service, model, route, database, or module works a certain way based only on filenames or this document.

1. Core Working Rule

Inspect first. Trace second. Change third. Validate last.

For every non-trivial task:

Inspect the relevant repository files.

Trace the actual call path.

Identify shared dependencies.

Determine the root cause.

Make the smallest correct change.

Run appropriate validation.

Review for regressions.

Do not make speculative fixes.

Do not perform large rewrites when a targeted correction will solve the problem.

Do not replace stable architecture simply because another approach appears newer.

2. Repository Discovery

At the beginning of a task involving an unfamiliar module, determine the actual project structure.

Inspect for:

Flutter/Dart applications;

web applications;

backend services;

Firebase configuration;

Firestore usage;

Realtime Database usage;

local SQLite/offline storage;

REST or FastAPI services;

Cloud Functions;

authentication and authorization;

AI/ML services;

OCR services;

reporting/export services;

storage/upload services;

test directories;

CI workflows;

environment configuration.

Do not assume every technology listed above is active.

Verify actual usage from imports, route registration, service calls, configuration, and runtime paths.

3. Protected Areas

Do not modify the following unless the requested task requires it and the change is justified by a verified issue:

database schemas;

database relationships;

authentication architecture;

authorization rules;

production API contracts;

existing stored data formats;

working backend business logic;

AI safety boundaries;

OCR verification requirements;

report data semantics;

audit/history logic;

synchronization semantics.

A UI task is not permission to refactor backend architecture.

A performance task is not permission to weaken validation or security.

A failing permission check is not permission to disable security rules.

4. CHO and BHW Role Boundaries

CHO and BHW are separate application roles with different responsibilities.

Whenever modifying a feature:

verify which role owns the action;

verify which role can read the data;

verify which role can create, update, approve, archive, or delete records;

verify that authorization is enforced beyond the UI;

do not rely only on hidden buttons or hidden routes for access control;

preserve role-specific workflows;

do not accidentally expose CHO-only data or actions to BHW users;

do not accidentally remove required BHW access.

If permissions are unclear, trace the current authorization logic before changing it.

5. Data Integrity

Health-related data must be treated as important structured data.

For create/update/delete operations:

validate required fields;

validate expected formats;

prevent accidental duplicate submissions;

prevent silent overwrites when unsafe;

use transactions or atomic operations where required;

preserve record identifiers;

preserve timestamps and audit metadata where already implemented;

never silently discard failed writes;

surface actionable errors to the appropriate layer;

do not log sensitive record contents unnecessarily.

When editing model classes, serializers, Firestore mappings, JSON mappings, or SQLite mappings, verify backward compatibility with existing stored records.

6. Backend and Service Reliability

For each backend/service flow, verify:

request construction;

authorization;

input validation;

timeouts;

retries;

duplicate request behavior;

error mapping;

response parsing;

null handling;

exception handling;

loading/success/error states;

cancellation/disposal where applicable.

Avoid broad empty exception handlers such as:

try {
  ...
} catch (_) {}

Do not swallow failures.

Errors should be classified where practical, for example:

validation;

authentication;

authorization;

unavailable network;

timeout;

not found;

conflict;

server failure;

parsing failure;

unknown failure.

User-facing errors should remain understandable and should not expose internal stack traces, credentials, or sensitive data.

7. Firebase Rules

If Firebase is present, inspect actual usage before changing configuration.

For Firebase-backed features:

preserve authentication;

verify role-based authorization;

review Firestore Security Rules where relevant;

review Storage Rules where relevant;

review Realtime Database Rules where relevant;

do not open a collection/database globally to make a feature work;

ensure queries match intended indexes;

avoid unnecessary reads;

avoid duplicate listeners;

dispose listeners when no longer needed;

use batch writes or transactions when consistency requires them.

Test security behavior with local/emulator tooling when the repository supports it.

8. Offline-First and SQLite Rules

If the BHW application uses local SQLite/offline queues, preserve offline-first behavior.

Critical scenario:

online
  -> go offline
  -> create or edit a record
  -> store locally
  -> queue sync operation
  -> reconnect
  -> synchronize
  -> verify remote record
  -> verify CHO can access expected data

Requirements:

never silently delete unsynchronized records;

preserve pending operations across application restarts;

make retry behavior safe;

prevent duplicate synchronization;

distinguish pending, syncing, synced, and failed states where the current design supports them;

handle partial failures;

avoid retry loops with no backoff or termination;

avoid overwriting newer remote changes without an explicit conflict strategy;

record enough sync metadata to diagnose failures without exposing sensitive data.

When modifying synchronization code, test:

create offline;

edit offline;

multiple queued records;

reconnect;

network interruption during sync;

failed server write;

duplicate retry;

application restart before sync;

application restart during pending state;

conflicting local/remote edits if the system supports edits from both sides.

9. Flutter Rules

For Flutter/Dart work:

follow the existing state-management approach unless a task explicitly requires migration;

avoid introducing a second state-management architecture without justification;

keep business logic out of presentation widgets where practical;

reuse existing services/repositories;

dispose controllers, streams, focus nodes, text controllers, timers, and subscriptions correctly;

avoid unnecessary widget rebuilds;

do not perform expensive synchronous work on the UI thread;

keep asynchronous state transitions predictable;

preserve navigation behavior;

preserve platform behavior for Android/iOS.

Before considering Flutter work complete, run the applicable commands from the correct project directory:

flutter pub get
flutter analyze
flutter test

If integration tests exist, run the relevant integration test command for the repository.

Do not claim success if flutter analyze or the relevant test suite reports newly introduced failures.

10. Web Application Rules

If this repository contains CHO/BHW web modules:

inspect the actual framework before making framework-specific changes;

preserve current routing;

preserve authentication;

preserve authorization;

avoid rewriting working pages only for stylistic reasons;

keep API/data contracts compatible;

preserve responsive behavior;

validate loading, empty, success, and error states;

verify route guards after changes.

Use the repository's existing package manager and scripts.

Discover commands from files such as:

package.json;

pubspec.yaml;

composer.json;

project README;

CI configuration.

Do not invent build commands that the repository does not use.

11. AI and Machine Learning Rules

AI-related changes must be measurable.

Do not claim that an AI feature is "more accurate", "better", or "improved" without evaluation evidence.

Before changing an active AI component:

identify the active inference path;

identify disabled/research-only model paths;

identify input features;

identify preprocessing;

identify output interpretation;

identify confidence handling;

establish a baseline evaluation;

implement the change;

rerun the same evaluation;

compare results.

Do not automatically enable research or disabled prediction models.

Do not turn a supportive guidance feature into autonomous diagnosis.

Do not add medication/prescription recommendations unless explicitly required, medically governed, and approved by the project requirements.

Low-confidence or unsupported AI output must not be represented as certain.

Where applicable, use a manual review or safe fallback.

12. Model Evaluation

For supervised classification models, evaluate at minimum:

dataset size;

class distribution;

train/validation/test separation;

duplicate samples;

missing values;

label consistency;

feature leakage;

preprocessing consistency;

accuracy;

precision;

recall;

F1 score;

confusion matrix;

per-class performance;

false positives;

false negatives;

confidence/calibration when relevant.

Do not optimize only for aggregate accuracy.

Inspect weak classes.

When the dataset is imbalanced, report metrics that expose minority-class performance.

Training-time preprocessing and inference-time preprocessing must match.

Keep an evaluation artifact or repeatable evaluation script where practical.

13. AI Safety Boundary

AI output in this system should support health workers and administrators, not replace qualified clinical judgment.

Do not:

fabricate medical facts;

present uncertain results as confirmed diagnoses;

fabricate citations;

prescribe treatments autonomously;

hide model limitations;

silently convert low-confidence results into final records.

If the existing system uses AI for guidance or support, preserve that boundary.

14. Google ML Kit OCR Rules

If Google ML Kit Text Recognition is used, optimize the entire OCR pipeline rather than only the recognizer call.

OCR flow should be treated as:

capture/import image
  -> image quality validation
  -> orientation correction
  -> crop/document boundary handling
  -> text recognition
  -> structural parsing
  -> field mapping
  -> normalization
  -> validation
  -> confidence/review state
  -> user verification
  -> save

Do not automatically trust raw OCR output.

Do not use only a single unstructured text blob if ML Kit blocks, lines, elements, positions, or other structure can improve field mapping.

15. OCR Accuracy Requirements

OCR changes must be evaluated using representative forms.

Create or maintain a safe OCR evaluation set that does not expose real patient data unnecessarily.

Include representative samples such as:

clear scans;

normal phone photographs;

slightly blurred captures;

low-light captures;

rotated pages;

perspective distortion;

partially completed forms;

different device cameras;

printed values;

handwriting only where the selected OCR capability can reasonably support it.

Measure accuracy at the field level, not only whether text was detected.

Examples of fields to validate:

names;

dates;

numeric measurements;

sex/gender option values if present;

barangay/location values;

identifiers;

phone numbers;

categorical fields;

form-specific health record values.

Track which fields fail most frequently.

Improve the actual failure modes.

16. OCR Field Mapping

Use field-aware extraction.

Field extraction may consider:

recognized text;

nearby labels;

line structure;

bounding boxes;

expected field location;

expected type;

regex/patterns;

known option lists;

neighboring text;

semantic validation.

Examples:

A date field should parse as a valid expected date.

A numeric field should reject impossible text values.

A barangay field should be validated against the system's valid barangay list if such a source exists.

A phone number should be normalized only when the input matches an acceptable pattern.

Do not force uncertain OCR output into a valid-looking value.

17. OCR Confidence and Manual Verification

OCR must retain human verification.

Where confidence or reliability can be estimated:

high-confidence values may be prefilled;

uncertain values should be highlighted for review;

low-confidence values should not be silently accepted;

users must be able to correct extracted values before save.

Never make OCR auto-save directly into authoritative health records without the required verification step.

18. Document Capture

If a document-scanning flow is already used or can be safely integrated without unnecessary architecture changes, it may be used to improve:

document boundary detection;

cropping;

rotation;

perspective;

image clarity;

capture consistency.

Do not replace a stable OCR stack merely because another library exists.

Evaluate improvements against the same OCR test set.

19. Performance Rules

Profile before optimizing.

Look for verified issues such as:

duplicate network requests;

unnecessary Firestore reads;

duplicate listeners;

unbounded queries;

loading entire collections when pagination is possible;

repeated expensive widget rebuilds;

large uncompressed images;

OCR running more times than necessary;

synchronous CPU-heavy work on the main isolate;

memory leaks;

large in-memory lists;

repeated model initialization;

repeated service initialization;

duplicate API calls caused by rebuilds;

unnecessary polling.

Do not sacrifice correctness, authorization, or data integrity for speed.

20. Logging and Observability

Important failures should be diagnosable.

Use structured, concise logs where the project supports them.

Useful events may include:

authentication failure category;

authorization denial;

sync attempt;

sync success/failure;

API timeout;

service unavailable;

OCR processing failure;

OCR parsing failure;

AI service failure;

export failure.

Do not log:

passwords;

access tokens;

API secrets;

entire patient records;

sensitive health information unless explicitly required by a protected audit mechanism.

Never print secret configuration values during debugging.

21. Secrets

Never hardcode secrets into application source.

This includes:

API keys;

private tokens;

service-account secrets;

database passwords;

signing secrets.

Use the repository's existing secure configuration method.

Do not commit .env secrets.

Do not expose secrets in generated documentation or logs.

If a secret is found committed in source, report it and use the project's intended secret-management approach rather than propagating it.

22. UI/UX Consistency

When working on UI/UX, CHO, BHW, web, and Flutter should share one coherent visual language.

Standardize where appropriate:

typography;

colors;

headings;

subheadings;

descriptions;

labels;

page headers;

buttons;

icons;

cards;

tables;

forms;

navigation;

spacing;

active states;

loading/empty/error states.

All important text must remain readable and visible.

Page headers should maintain adequate contrast.

Navigation must clearly indicate the current page/section.

Uniformity means consistent design rules, not forcing every workflow to look identical.

Do not introduce generic AI-generated visual clutter.

23. 21st.dev MCP

If the 21st MCP server is configured and available, it may be used for UI/UX research and comparison.

Use it primarily for:

layout inspiration;

component composition;

navigation patterns;

active sidebar states;

typography hierarchy;

cards;

data tables;

forms;

dialogs;

dashboards;

responsive behavior;

mobile interaction patterns.

Do not blindly copy components.

Do not copy React/Next.js/Tailwind/shadcn implementation directly into Flutter.

For Flutter, extract the design principle and implement the equivalent using native Flutter/Dart.

21st.dev examples are references, not project requirements.

Do not add features merely because a reference contains them.

24. Testing Strategy

Use tests to protect important behavior.

Prefer meaningful coverage over artificial coverage numbers.

Prioritize tests for:

authentication;

CHO authorization;

BHW authorization;

record creation;

record updates;

record retrieval;

offline queue;

synchronization;

duplicate prevention;

OCR mapping;

OCR field validation;

AI preprocessing;

AI inference handling;

AI fallback behavior;

reports/exports;

critical navigation.

For Flutter, use a combination of:

unit tests;

widget tests;

integration tests.

For backend services, use the test framework already present in that service.

Do not introduce a new testing framework unnecessarily.

25. Critical End-to-End Scenarios

When applicable, validate these scenarios after substantial backend changes.

Authentication

launch
-> login
-> role resolved
-> correct portal opened
-> unauthorized portal blocked
-> logout

BHW Record Flow

BHW login
-> create/update permitted record
-> validation
-> save
-> reload
-> verify persisted data

Offline Flow

BHW login
-> connection lost
-> create/edit record
-> local save
-> queued state
-> app restart if applicable
-> reconnect
-> sync
-> remote verification
-> CHO visibility where permitted

OCR Flow

capture/import form
-> OCR
-> field mapping
-> confidence/review
-> manual correction
-> validation
-> save
-> reopen record

AI Flow

valid input
-> preprocessing
-> inference/guidance
-> output validation
-> confidence/fallback
-> UI presentation

Test invalid and unavailable-service cases as well.

26. Static Analysis and Build Validation

Before finishing a code task, run applicable validation.

For Flutter projects, normally:

flutter pub get
flutter analyze
flutter test

For other project types, discover the repository's commands from its configuration and CI.

Examples may include linting, tests, type checks, and builds.

Do not report a task as complete while knowingly leaving newly introduced analyzer errors, test failures, or build failures.

If unrelated pre-existing failures exist, distinguish them clearly from failures introduced by the current changes.

27. Regression Rule

A successful improvement must not break another module.

After modifying a shared service, theme, model, route, serializer, synchronization component, or reusable widget, identify its consumers and validate affected paths.

Pay particular attention to changes in:

shared models;

shared Firebase services;

authentication;

routing;

database mappings;

offline queues;

reusable Flutter widgets;

API clients;

AI preprocessing;

OCR parsing;

report generation.

28. Code Quality

Prefer:

clear naming;

small focused functions;

reusable components;

centralized constants;

explicit state transitions;

testable services;

typed data structures;

predictable error behavior.

Avoid:

massive functions;

duplicated business logic;

duplicated API calls;

deeply nested conditionals when simpler structure exists;

magic strings scattered throughout the project;

magic numeric values without meaning;

silent exceptions;

dead code;

unused imports;

temporary debugging output left in production paths.

Do not over-engineer simple functionality.

29. Refactoring

Refactoring is allowed when it directly improves:

correctness;

reliability;

testability;

maintainability;

reusability;

performance;

UI consistency.

Before a significant refactor:

identify the behavior that must remain unchanged;

establish tests or validation for that behavior;

make the refactor;

rerun validation;

inspect affected consumers.

Do not combine unrelated architectural rewrites with a targeted bug fix.

30. Database Migration Rule

Do not create or execute destructive database migrations casually.

If a schema/data migration is genuinely required:

explain why existing structure cannot support the required behavior;

preserve existing production data;

provide a rollback or recovery path where practical;

test migration against representative non-production data;

update serialization/model code together;

validate old and new records where backward compatibility is required.

Never delete production data merely to simplify development.

31. Reports and Exports

Reports must reflect stored data accurately.

When modifying reports:

do not alter data semantics for visual convenience;

preserve filters;

preserve date ranges;

preserve role restrictions;

verify totals and aggregates;

verify empty-data behavior;

verify page layout;

verify generated files can be opened;

prevent accidental disclosure of data outside the authorized scope.

32. Accessibility and Readability

All interfaces should maintain:

readable font sizes;

adequate contrast;

visible headings;

visible descriptions;

clear button labels;

usable touch targets;

meaningful active states;

appropriate semantic labels where supported.

Do not reduce readability to fit more content on screen.

33. No Fake Data or Features

Do not introduce fake operational data to make dashboards look complete.

Do not add:

fake metrics;

fake patient counts;

fake alerts;

fake analytics;

fake AI results;

placeholder records in production code;

unrequested modules.

Use mock data only inside clearly isolated development/test fixtures.

34. Completion Checklist

Before marking substantial work complete, verify the applicable items:

inspected the actual implementation;

traced affected call paths;

preserved CHO/BHW role boundaries;

preserved backend/data contracts unless explicitly required;

preserved offline behavior;

handled errors;

avoided secret exposure;

added or updated meaningful tests where needed;

ran static analysis;

ran relevant test suites;

checked affected routes;

checked affected database operations;

checked synchronization if touched;

checked OCR evaluation if OCR changed;

checked AI evaluation if AI changed;

checked responsive behavior if UI changed;

checked shared-component regressions;

removed temporary debugging code;

reviewed the final diff for unrelated changes.

35. Final Review Standard

The goal is not maximum code churn.

The goal is a system that is:

correct;

reliable;

secure;

maintainable;

testable;

responsive;

visually consistent;

usable online and offline where required;

transparent about AI uncertainty;

careful with OCR uncertainty;

resistant to regressions.

When uncertain, prefer preserving known working behavior while investigating the root cause.

Do not claim an issue is fixed until the affected workflow has been validated.