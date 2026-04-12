#!/bin/bash
flutter run -d macos \
  --dart-define=SUPABASE_URL=https://bfvcscssepfuqmbffqmg.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdmNzY3NzZXBmdXFtYmZmcW1nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwMDQ3ODcsImV4cCI6MjA5MDU4MDc4N30.Ic10ZcUSuYw_kPfhwuvpVoPyG_5b-dKwPS3s578eUcM \
  --dart-define=API_BASE_URL=https://paintmatch-production.up.railway.app
