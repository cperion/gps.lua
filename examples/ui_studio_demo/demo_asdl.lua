local ui_asdl = require("ui.asdl")

local T = ui_asdl.T

T:Define [[
    module Studio {
        Selection = SelNone
                  | SelTransport
                  | SelBrowser(number index) unique
                  | SelTrack(number index) unique
                  | SelScene(number index) unique
                  | SelClip(number track_index, number scene_index) unique
                  | SelDevice(number index) unique

        DeviceKind = Instrument | Mixer | Mod | Fx
        ThemeMode = ThemeDark | ThemeLight

        BrowserItem = (string title,
                       string tag,
                       string note) unique

        Track = (string name,
                 string short,
                 string route,
                 string group) unique

        Scene = (string name,
                 string short,
                 string length) unique

        Device = (Studio.DeviceKind kind,
                  string name,
                  string summary) unique

        App = (string project_name,
               number bpm,
               boolean playing,
               Studio.ThemeMode theme_mode,
               Studio.Selection selection,
               Studio.BrowserItem* browser_items,
               Studio.Track* tracks,
               Studio.Scene* scenes,
               Studio.Device* devices,
               string* logs) unique

        State = (Studio.App app,
                 Interact.Model ui_model) unique

        Event = FocusSelection(Studio.Selection selection) unique
              | ActivateSelection(Studio.Selection selection) unique
              | ToggleTheme unique
    }

    module StudioView {
        Tone = ToneBlue | ToneAmber | ToneGreen | ToneRose | ToneNeutral

        TopStat = (string label,
                   string value,
                   string suffix,
                   StudioView.Tone tone) unique

        BrowserMeta = (string label,
                       string value) unique

        InspectorStat = (string label,
                         string value,
                         StudioView.Tone tone) unique

        ActivityItem = (string text) unique

        BrowserRow = (number index,
                      Studio.BrowserItem item,
                      boolean selected,
                      boolean hovered,
                      boolean focused) unique

        TrackHeader = (number index,
                       Studio.Track track,
                       boolean selected,
                       boolean hovered,
                       boolean focused) unique

        SceneButton = (number index,
                       Studio.Scene scene,
                       boolean selected,
                       boolean hovered,
                       boolean focused) unique

        ClipCell = (number track_index,
                    number scene_index,
                    Studio.Track track,
                    Studio.Scene scene,
                    number level_a,
                    number level_b,
                    number level_c,
                    number playhead,
                    boolean armed,
                    boolean selected,
                    boolean hovered,
                    boolean focused) unique

        DeviceCard = (number index,
                      Studio.Device device,
                      number macro_a,
                      number macro_b,
                      number macro_c,
                      boolean selected,
                      boolean hovered,
                      boolean focused) unique

        Branding = (string title,
                    string subtitle) unique

        Waveform = (string title,
                    number* samples,
                    number playhead,
                    StudioView.Tone tone) unique

        Topbar = (StudioView.Branding branding,
                  string project_name,
                  boolean playing,
                  StudioView.TopStat* stats) unique

        BrowserPanel = (StudioView.BrowserMeta* meta,
                        StudioView.BrowserRow* rows) unique

        LauncherPanel = (StudioView.TrackHeader* tracks,
                         StudioView.SceneButton* scenes,
                         StudioView.ClipCell* clips) unique

        InspectorPanel = (string title,
                          string summary,
                          StudioView.InspectorStat* stats,
                          StudioView.Waveform waveform,
                          StudioView.DeviceCard* devices,
                          string notes) unique

        Dock = (StudioView.DeviceCard* devices,
                StudioView.Waveform waveform,
                StudioView.ActivityItem* logs) unique

        Workspace = (StudioView.Topbar topbar,
                     StudioView.BrowserPanel browser,
                     StudioView.LauncherPanel launcher,
                     StudioView.InspectorPanel inspector,
                     StudioView.Dock dock) unique
    }
]]

return {
    T = T,
}
