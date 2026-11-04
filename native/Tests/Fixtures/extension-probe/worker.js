chrome.runtime.onMessage.addListener((message, _sender, reply) => {
  if (message.type !== 'probe') return;
  chrome.storage.local.get({count: 0}).then(async ({count}) => {
    await chrome.storage.local.set({count: count + 1});
    reply({count: count + 1, worker: 'Manifest V3 actif'});
  });
  return true;
});
