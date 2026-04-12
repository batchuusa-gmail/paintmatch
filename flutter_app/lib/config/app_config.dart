class AppConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bfvcscssepfuqmbffqmg.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdmNzY3NzZXBmdXFtYmZmcW1nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwMDQ3ODcsImV4cCI6MjA5MDU4MDc4N30.Ic10ZcUSuYw_kPfhwuvpVoPyG_5b-dKwPS3s578eUcM',
  );
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://paintmatch-production.up.railway.app',
  );

  /// Number of free renders before auth gate kicks in
  static const int freeRenderLimit = 3;
}
