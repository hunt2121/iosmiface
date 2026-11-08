// SPDX-License-Identifier: MIT
// Проєкт — звичайна тека: меню «Файл» (тека в Провіднику, перенесення, .bin) і стеження за змінами ззовні.

using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace BandFace.Creator
{
    public partial class EditorView
    {
        FileSystemWatcher watcher;
        DispatcherTimer reloadTimer;

        /// <summary>Стежить за текою відкритого проєкту: зміни ззовні підхоплюються через пів секунди тиші</summary>
        void Watch()
        {
            watcher?.Dispose();
            watcher = null;
            if (project?.Folder == null || !Directory.Exists(project.Folder)) return;
            if (reloadTimer == null)
            {
                reloadTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
                reloadTimer.Tick += (s, e) =>
                {
                    reloadTimer.Stop();
                    // поки тягнуть мишею — не заважаємо
                    if (project == null || dragLayout != null || handle != null) { reloadTimer.Start(); return; }
                    project.ReloadFromDisk();
                };
            }
            try
            {
                watcher = new FileSystemWatcher(project.Folder) { IncludeSubdirectories = true, NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite | NotifyFilters.Size };
                FileSystemEventHandler h = (s, e) => Dispatcher.BeginInvoke(new Action(() => { reloadTimer.Stop(); reloadTimer.Start(); }));
                watcher.Changed += h; watcher.Created += h; watcher.Deleted += h;
                watcher.Renamed += (s, e) => h(s, e);
                watcher.EnableRaisingEvents = true;
            }
            catch (Exception) { watcher = null; }
        }

        /// <summary>Закрито редактор: більше не стежимо</summary>
        public void StopWatching() { watcher?.Dispose(); watcher = null; reloadTimer?.Stop(); }

        void File_Click(object sender, RoutedEventArgs e)
        {
            if (project == null) return;
            var menu = new ContextMenu();
            Ui.MenuBelow(menu, FileBtn, alignRight: true);
            Ui.MenuAdd(menu, S.Get("openProjectFolder"), "\uE838", () => { try { Process.Start("explorer.exe", "\"" + project.Folder + "\""); } catch (Exception) { } });
            Ui.MenuAdd(menu, S.Get("moveProject"), "\uE8DE", MoveProject);
            menu.Items.Add(new Separator());
            Ui.MenuAdd(menu, S.Get("saveBin"), "\uE74E", () => Actions.ExportBin(Owner, project));
            menu.Items.Add(new Separator());
            Ui.MenuPath(menu, project.Folder);
            menu.IsOpen = true;
        }

        void MoveProject()
        {
            using (var dlg = new System.Windows.Forms.FolderBrowserDialog { Description = S.Get("moveProjectTitle"), ShowNewFolderButton = true })
            {
                if (dlg.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;
                StopWatching();
                try { ProjectStore.Move(project, dlg.SelectedPath); }
                catch (Exception ex) { MessageBox.Show(Owner, S.Get("moveFail", ex.Message), "BandFace", MessageBoxButton.OK, MessageBoxImage.Error); }
                Watch();
                RefreshAll();
            }
        }
    }
}
