import { vpnExtension } from '@kit.NetworkKit';

export class VpnAuthorization {
  // API 26 crashes in CreateVpnObserver's native finalizer during idle GC if
  // observers are discarded. Retain one observer for the UI process lifetime
  // and unsubscribe callbacks after each authorization attempt.
  private static observer?: vpnExtension.VpnObserver;

  static subscribe(callback: (authorized: boolean) => void): void {
    try {
      if (!VpnAuthorization.observer) {
        VpnAuthorization.observer = vpnExtension.createVpnObserver();
      }
      VpnAuthorization.observer.onAuthorizationResult(callback);
    } catch (_err) {
      // Older emulators or mocked host runtimes may not expose createVpnObserver.
    }
  }

  static unsubscribe(): void {
    try {
      VpnAuthorization.observer?.offAuthorizationResult();
    } catch (_err) {
      // Ignore cleanup errors on teardown.
    }
  }
}
