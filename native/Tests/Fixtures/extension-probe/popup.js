async function verify() {
  const result = await chrome.runtime.sendMessage({type: 'probe'});
  document.querySelector('#status').textContent = `${result.worker} · compteur persistant : ${result.count}`;
}
document.querySelector('#test').addEventListener('click', verify);
document.querySelector('#background-tab').addEventListener('click', async () => {
  const label = document.querySelector('#tab-status');
  try {
    const created = await chrome.tabs.create({url: 'https://example.com/', active: false});
    const readBack = await chrome.tabs.get(created.id);
    label.textContent = `Onglet ${readBack.id} créé et retrouvé par Chromium.`;
  } catch (error) {
    label.textContent = `Échec : ${error.message}`;
  }
});
verify();
