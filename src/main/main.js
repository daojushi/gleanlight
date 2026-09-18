const path = require('node:path');
const { app, BrowserWindow, ipcMain } = require('electron');
const { Database } = require('./database');
const { Repository } = require('./repository');

let repository;

async function boot() {
  const database = new Database(path.join(app.getPath('userData'), 'its.sqlite'));
  await database.open();
  repository = new Repository(database);

  const window = new BrowserWindow({
    width: 1280, height: 820, minWidth: 920, minHeight: 640,
    backgroundColor: '#f5f4ef',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false },
  });
  await window.loadFile(path.join(__dirname, '../renderer/index.html'));
}

app.whenReady().then(boot);
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) boot(); });

ipcMain.handle('data:list', (_, type) => repository.list(type));
ipcMain.handle('data:save', (_, type, input) => repository.save(type, input));
ipcMain.handle('data:remove', (_, type, id) => repository.remove(type, id));
ipcMain.handle('topic:list', () => repository.listTopics());
ipcMain.handle('topic:save', (_, input) => repository.saveTopic(input));
ipcMain.handle('topic:detail', (_, id) => repository.topicDetail(id));
