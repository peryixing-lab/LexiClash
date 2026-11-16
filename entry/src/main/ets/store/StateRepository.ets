import { fileIo as fs } from '@kit.CoreFileKit';

// Configurations exceed Preferences' string limits. Atomically replace a file in the app sandbox instead.
export class StateRepository {
  private filePath: string = '';
  private lastSaved: string = '';
  errorMessage: string = '';

  initialize(filesDir: string): string {
    this.filePath = filesDir + '/lexiclash-state.json';
    try {
      if (!fs.accessSync(this.filePath)) { return ''; }
      const raw: string = fs.readTextSync(this.filePath);
      this.lastSaved = raw;
      return raw;
    } catch (error) {
      this.errorMessage = '无法读取本地配置：' + (error as Error).message;
      return '';
    }
  }

  save(raw: string): void {
    if (this.filePath.length === 0 || raw === this.lastSaved) { return; }
    const temporary: string = this.filePath + '.tmp';
    try {
      const file: fs.File = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, raw); } finally { fs.closeSync(file); }
      fs.renameSync(temporary, this.filePath);
      this.lastSaved = raw;
      this.errorMessage = '';
    } catch (error) {
      this.errorMessage = '无法保存本地配置：' + (error as Error).message;
    }
  }
}
