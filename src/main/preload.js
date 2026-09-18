const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('its', {
  list: type => ipcRenderer.invoke('data:list', type),
  save: (type, input) => ipcRenderer.invoke('data:save', type, input),
  remove: (type, id) => ipcRenderer.invoke('data:remove', type, id),
  listTopics: () => ipcRenderer.invoke('topic:list'),
  saveTopic: input => ipcRenderer.invoke('topic:save', input),
  topicDetail: id => ipcRenderer.invoke('topic:detail', id),
});
