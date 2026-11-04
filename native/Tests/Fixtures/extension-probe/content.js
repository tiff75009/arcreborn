const badge = document.createElement('aside');
badge.id = 'browser-extension-probe';
badge.textContent = 'Browser : script d’extension actif';
badge.style.cssText = 'position:fixed;bottom:20px;right:20px;background:#653d89;color:white;padding:16px;border-radius:12px;font:16px system-ui;z-index:2147483647';
document.documentElement.append(badge);
