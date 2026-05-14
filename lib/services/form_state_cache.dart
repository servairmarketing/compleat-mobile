/// Bug #14 — transaction-screen state preservation across navigation.
///
/// Transaction screens are pushed with `Navigator.push`, so navigating away
/// (e.g. to Home) disposes the screen's State and returning rebuilds it
/// fresh — losing everything the operator had typed.
///
/// This is a process-lifetime, in-memory only cache keyed by screen name.
/// It is intentionally NOT persisted to Firestore, SharedPreferences or
/// disk — values are lost on app close, which is the desired behaviour.
///
/// Usage pattern per screen:
///  - `initState`: read the snapshot (if any) and repopulate controllers /
///    selection state.
///  - `dispose`: write a snapshot of the current field values BEFORE
///    disposing the controllers.
///  - on successful submit / explicit Clear: call [clear] so the next
///    entry starts blank.
class FormStateCache {
  FormStateCache._();

  static final Map<String, Map<String, dynamic>> _store = {};

  /// Snapshot for [key], or null if nothing stored.
  static Map<String, dynamic>? read(String key) => _store[key];

  /// Store (or replace) the snapshot for [key].
  static void write(String key, Map<String, dynamic> data) {
    _store[key] = data;
  }

  /// Drop the snapshot for [key] — call after a successful submit or when
  /// the operator explicitly resets the form.
  static void clear(String key) => _store.remove(key);
}
