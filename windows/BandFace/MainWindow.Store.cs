using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using BandFace.Protocol;
using BandFace.Store;

namespace BandFace
{
    /// <summary>Вкладка «Магазин»: те, що магазину потрібно від головного вікна (браслет, встановлення, вибір, видалення)</summary>
    public partial class MainWindow : IStoreHost
    {
        StoreView StoreTab;

        /// <summary>Сторінка магазину — поруч з іншими сторінками вкладок</summary>
        void InitStore()
        {
            StoreTab = new StoreView { Host = this, Visibility = Visibility.Collapsed };
            PagesHost.Children.Add(StoreTab);
            NavStore.IsEnabled = true;
            StoreChip.Visibility = Visibility.Collapsed;
            NavStore.ToolTip = null;
        }

        int IStoreHost.BandModel
        {
            get
            {
                var m = Regex.Match(_ble.ConnectedName ?? "", @"Band\s*(\d+)", RegexOptions.IgnoreCase);
                return m.Success && int.TryParse(m.Groups[1].Value, out var n) ? n : 10;
            }
        }

        bool IStoreHost.CanOperate => _ble.IsConnected && !_connecting && KeyValid;
        bool IStoreHost.Busy => _busy;
        string IStoreHost.ActiveId => _activeId;
        IReadOnlyCollection<string> IStoreHost.InstalledIds => _installedIds;

        /// <summary>Встановлення з магазину тим самим шляхом, що й з вкладки «Циферблати»;
        /// циферблат з тим самим ID на браслеті замінюється (оновлення)</summary>
        async Task<string> IStoreHost.InstallAsync(FaceFile face, string name, Action<Creator.InstallUpdate> report)
        {
            if (_busy) return S.Get("errConnect");
            if (!LoadFace(face.Data, name + ".bin")) return S.Get("errFace");
            Creator.InstallUpdate last = null;
            _replaceExisting = true;
            try { await InstallAsync(u => { last = u; report?.Invoke(u); }, name); }
            finally { _replaceExisting = false; }
            if (last?.State == Creator.InstallUpdate.Kind.Done) return null;
            if (last?.State == Creator.InstallUpdate.Kind.Cancelled) return "";
            return last?.Error ?? S.Get("errConnect");
        }

        Task<string> IStoreHost.ActivateAsync(string faceId) => BandCommandAsync(Command.ActivateWatchface(faceId));
        Task<string> IStoreHost.DeleteAsync(string faceId) => BandCommandAsync(Command.DeleteWatchface(faceId));

        void IStoreHost.EditCopy(byte[] bin, string name)
        {
            NavEditor.IsChecked = true;
            EditorTab.OpenCopy(bin, name);
        }

        /// <summary>Одна команда браслету (вибрати або видалити циферблат), потім — новий список циферблатів на ньому</summary>
        async Task<string> BandCommandAsync(byte[] command)
        {
            var key = Bytes.ParseHex(KeyBox.Text);
            if (key == null || key.Length != 16) return S.Get("keyInvalid");
            if (!_ble.IsConnected || _connecting) return S.Get("errConnect");
            if (_busy) return S.Get("errConnect");
            await _bandGate.WaitAsync();
            _busy = true;
            StoreTab?.BandChanged();
            var session = new BandSession(_ble, NewConfig());
            _session = session;
            try
            {
                await session.OpenAsync();
                await session.AuthenticateAsync(key, "Windows PC", "UK", Command.PhoneInfoMiFitness(Region()));
                try { await session.CommandAsync(Command.AfterAuthMiFitness, 3000); } catch (BandException) { }
                await session.CommandAsync(command);
                var list = WatchfaceEntry.List(await session.CommandAsync(Command.WatchfaceListRequest()));
                try { await session.CloseAsync(); } catch (Exception) { }
                _lastFaceSync = DateTime.Now;
                var active = list.FirstOrDefault(x => x.IsActive)?.Id;
                _installedIds = list.Select(x => x.Id).ToList();
                EditorTab.SetActiveFace(active);
                EditorTab.SetInstalledFaces(_installedIds);
                SetActiveId(active);
                return null;
            }
            catch (Exception ex) { AddLog("store: " + ex.Message); return Describe(ex); }
            finally
            {
                try { session.Dispose(); } catch (Exception) { }
                _session = null;
                _busy = false;
                _bandGate.Release();
                RefreshBand();
                StoreTab?.BandChanged();
            }
        }
    }
}
