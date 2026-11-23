import { contextBridge, ipcRenderer } from 'electron';
import type { DesktopApi } from '../shared/model';

contextBridge.exposeInMainWorld('focusflow', {
  read: (query) => ipcRenderer.invoke('workspace:read', query),
  pulse: () => ipcRenderer.invoke('workspace:pulse'),
  command: (command) => ipcRenderer.invoke('workspace:command', command),
  backup: (action) => ipcRenderer.invoke('workspace:backup', action),
  onChime: (play: () => void) => {
    const listener = () => play();
    ipcRenderer.on('timer:chime', listener);
    return () => { ipcRenderer.removeListener('timer:chime', listener); };
  },
} satisfies DesktopApi);
