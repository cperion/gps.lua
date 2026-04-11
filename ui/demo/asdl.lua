-- ui/demo/asdl.lua
-- Richer DAW demo domain schema.
--
-- The demo now carries a more realistic project model with both raw/interchange
-- and normalized layers, even though the UI still mocks parts of the runtime.
-- The active demo currently renders from the normalized project plus explicit
-- hot runtime state in `Demo.State`.

local pvm = require("pvm")

local M = {}
local T = pvm.context()
M.T = T

T:Define [[
    module DawProjectCore {
        Id = (string value) unique
        Name = (string value) unique
        Comment = (string value) unique
        HtmlColor = (string value) unique
        Path = (string value) unique
        Version = (string value) unique

        Nameable = (
            string? name,
            string? color,
            string? comment
        ) unique

        Referenceable = (
            string? id,
            DawProjectCore.Nameable meta
        ) unique

        TimelineHeader = (
            string? id,
            string? name,
            string? color,
            string? comment,
            string? track,
            DawProjectCore.TimeUnit? time_unit
        ) unique

        ParameterHeader = (
            string? id,
            string? name,
            string? color,
            string? comment,
            number? parameter_id
        ) unique

        DeviceHeader = (
            string? id,
            string? name,
            string? color,
            string? comment,
            DawProjectCore.DeviceRole device_role,
            boolean? loaded,
            string device_name,
            string? device_id,
            string? device_vendor
        ) unique

        TrackHeader = (
            string? id,
            string? name,
            string? color,
            string? comment,
            DawProjectCore.ContentType* content_type,
            boolean? loaded
        ) unique

        ChannelHeader = (
            string? id,
            string? name,
            string? color,
            string? comment,
            DawProjectCore.ChannelRole? role,
            number? audio_channels,
            boolean? solo,
            string? destination
        ) unique

        SendHeader = (
            string? id,
            string? name,
            string? color,
            string? comment,
            DawProjectCore.SendType? type,
            string? destination
        ) unique

        TimeUnit = Beats | Seconds

        RealUnit = Linear | Normalized | Percent | Decibel
                 | Hertz | Semitones | SecondsUnit | BeatsUnit | BPM

        ContentType = AudioContent | AutomationContent | NotesContent
                    | VideoContent | MarkersContent | TracksContent

        ChannelRole = Regular | Master | Effect | Submix | VCA
        SendType = Pre | Post
        DeviceRole = Instrument | NoteFX | AudioFX | Analyzer
        Interpolation = Hold | LinearInterp

        ExpressionType = GainExpr | PanExpr | TransposeExpr
                       | TimbreExpr | FormantExpr | PressureExpr
                       | ChannelControllerExpr | ChannelPressureExpr
                       | PolyPressureExpr | PitchBendExpr | ProgramChangeExpr

        PluginFormat = AU | CLAP | VST2 | VST3 | GenericPlugin

        EqBandType = HighPass | LowPass | BandPass
                   | HighShelf | LowShelf | Bell | Notch
    }

    module DawProjectParams {
        Parameter = BoolParam(DawProjectParams.BoolParameter value)
                  | EnumParam(DawProjectParams.EnumParameter value)
                  | IntegerParam(DawProjectParams.IntegerParameter value)
                  | RealParam(DawProjectParams.RealParameter value)
                  | TimeSignatureParam(DawProjectParams.TimeSignatureParameter value)

        BoolParameter = (
            DawProjectCore.ParameterHeader header,
            boolean? value
        ) unique

        EnumParameter = (
            DawProjectCore.ParameterHeader header,
            number count,
            number? value,
            string* labels
        ) unique

        IntegerParameter = (
            DawProjectCore.ParameterHeader header,
            number? value,
            number? min,
            number? max
        ) unique

        RealParameter = (
            DawProjectCore.ParameterHeader header,
            DawProjectCore.RealUnit unit,
            number? value,
            number? min,
            number? max
        ) unique

        TimeSignatureParameter = (
            DawProjectCore.ParameterHeader header,
            number numerator,
            number denominator
        ) unique
    }

    module DawProjectAutomation {
        Points = (
            DawProjectCore.TimelineHeader header,
            DawProjectCore.RealUnit? unit,
            DawProjectAutomation.AutomationTarget target,
            DawProjectAutomation.Point* points
        ) unique

        AutomationTarget = (
            string? parameter,
            DawProjectCore.ExpressionType? expression,
            number? channel,
            number? key,
            number? controller
        ) unique

        Point = BoolPoint(DawProjectAutomation.BoolPoint value)
              | EnumPoint(DawProjectAutomation.EnumPoint value)
              | IntegerPoint(DawProjectAutomation.IntegerPoint value)
              | RealPoint(DawProjectAutomation.RealPoint value)
              | TimeSignaturePoint(DawProjectAutomation.TimeSignaturePoint value)

        BoolPoint = (number time, boolean value) unique
        EnumPoint = (number time, number value) unique
        IntegerPoint = (number time, number value) unique
        RealPoint = (number time, number value, DawProjectCore.Interpolation? interpolation) unique
        TimeSignaturePoint = (number time, number numerator, number denominator) unique
    }

    module DawProjectDevices {
        Device = AUPlugin(DawProjectDevices.AuPlugin device)
               | CLAPPlugin(DawProjectDevices.ClapPlugin device)
               | GenericPlugin(DawProjectDevices.Plugin device)
               | VST2Plugin(DawProjectDevices.Vst2Plugin device)
               | VST3Plugin(DawProjectDevices.Vst3Plugin device)
               | BuiltinDeviceNode(DawProjectDevices.BuiltinDevice device)
               | CompressorNode(DawProjectDevices.Compressor device)
               | EqualizerNode(DawProjectDevices.Equalizer device)
               | LimiterNode(DawProjectDevices.Limiter device)
               | NoiseGateNode(DawProjectDevices.NoiseGate device)

        Plugin = (
            DawProjectCore.DeviceHeader header,
            string? plugin_version,
            DawProjectParams.BoolParameter? enabled,
            DawProjectRoot.FileReference? state,
            DawProjectParams.Parameter* parameters
        ) unique

        AuPlugin = (DawProjectDevices.Plugin base) unique
        ClapPlugin = (DawProjectDevices.Plugin base) unique
        Vst2Plugin = (DawProjectDevices.Plugin base) unique
        Vst3Plugin = (DawProjectDevices.Plugin base) unique

        BuiltinDevice = (
            DawProjectCore.DeviceHeader header,
            DawProjectParams.BoolParameter? enabled,
            DawProjectRoot.FileReference? state,
            DawProjectParams.Parameter* parameters
        ) unique

        Compressor = (
            DawProjectDevices.BuiltinDevice base,
            DawProjectParams.RealParameter? threshold,
            DawProjectParams.RealParameter? ratio,
            DawProjectParams.RealParameter? attack,
            DawProjectParams.RealParameter? release,
            DawProjectParams.RealParameter? input_gain,
            DawProjectParams.RealParameter? output_gain,
            DawProjectParams.BoolParameter? auto_makeup
        ) unique

        Equalizer = (
            DawProjectDevices.BuiltinDevice base,
            DawProjectDevices.EqBand* bands,
            DawProjectParams.RealParameter? input_gain,
            DawProjectParams.RealParameter? output_gain
        ) unique

        EqBand = (
            DawProjectCore.EqBandType type,
            number? order,
            DawProjectParams.RealParameter freq,
            DawProjectParams.RealParameter? gain,
            DawProjectParams.RealParameter? q,
            DawProjectParams.BoolParameter? enabled
        ) unique

        Limiter = (
            DawProjectDevices.BuiltinDevice base,
            DawProjectParams.RealParameter? threshold,
            DawProjectParams.RealParameter? input_gain,
            DawProjectParams.RealParameter? output_gain,
            DawProjectParams.RealParameter? attack,
            DawProjectParams.RealParameter? release
        ) unique

        NoiseGate = (
            DawProjectDevices.BuiltinDevice base,
            DawProjectParams.RealParameter? threshold,
            DawProjectParams.RealParameter? ratio,
            DawProjectParams.RealParameter? attack,
            DawProjectParams.RealParameter? release,
            DawProjectParams.RealParameter? range
        ) unique
    }

    module DawProjectMixer {
        Track = (
            DawProjectCore.TrackHeader header,
            DawProjectMixer.Channel? channel,
            DawProjectMixer.Track* tracks
        ) unique

        Channel = (
            DawProjectCore.ChannelHeader header,
            DawProjectParams.RealParameter? volume,
            DawProjectParams.RealParameter? pan,
            DawProjectParams.BoolParameter? mute,
            DawProjectMixer.Send* sends,
            DawProjectDevices.Device* devices
        ) unique

        Send = (
            DawProjectCore.SendHeader header,
            DawProjectParams.RealParameter volume,
            DawProjectParams.RealParameter? pan,
            DawProjectParams.BoolParameter? enable
        ) unique
    }

    module DawProjectTimeline {
        Arrangement = (
            DawProjectCore.Referenceable header,
            DawProjectAutomation.Points? time_signature_automation,
            DawProjectAutomation.Points? tempo_automation,
            DawProjectTimeline.Markers? markers,
            DawProjectTimeline.Lanes? lanes
        ) unique

        Scene = (
            DawProjectCore.Referenceable header,
            DawProjectTimeline.TimelineContent* content
        ) unique

        TimelineContent = AudioNode(DawProjectTimeline.Audio value)
                        | ClipSlotNode(DawProjectTimeline.ClipSlot value)
                        | ClipsNode(DawProjectTimeline.Clips value)
                        | LanesNode(DawProjectTimeline.Lanes value)
                        | MarkersNode(DawProjectTimeline.Markers value)
                        | MediaFileNode(DawProjectTimeline.MediaFile value)
                        | NotesNode(DawProjectTimeline.Notes value)
                        | PointsNode(DawProjectAutomation.Points value)
                        | VideoNode(DawProjectTimeline.Video value)
                        | WarpsNode(DawProjectTimeline.Warps value)

        ClipSlot = (
            DawProjectCore.TimelineHeader header,
            boolean? has_stop,
            DawProjectTimeline.Clip? clip
        ) unique

        Lanes = (
            DawProjectCore.TimelineHeader header,
            DawProjectTimeline.TimelineContent* lanes
        ) unique

        Clips = (
            DawProjectCore.TimelineHeader header,
            DawProjectTimeline.Clip* clips
        ) unique

        Clip = (
            DawProjectCore.Nameable meta,
            number time,
            number? duration,
            DawProjectCore.TimeUnit? content_time_unit,
            number? play_start,
            number? play_stop,
            number? loop_start,
            number? loop_end,
            DawProjectCore.TimeUnit? fade_time_unit,
            number? fade_in_time,
            number? fade_out_time,
            boolean? enable,
            string? reference,
            DawProjectTimeline.TimelineContent? content
        ) unique

        Notes = (
            DawProjectCore.TimelineHeader header,
            DawProjectTimeline.Note* notes
        ) unique

        Note = (
            number time,
            number duration,
            number? channel,
            number key,
            number? vel,
            number? rel,
            DawProjectTimeline.TimelineContent* expressions
        ) unique

        MediaFile = AudioMedia(DawProjectTimeline.Audio value)
                  | VideoMedia(DawProjectTimeline.Video value)

        Audio = (
            DawProjectCore.TimelineHeader header,
            number sample_rate,
            number channels,
            string? algorithm,
            number duration,
            DawProjectRoot.FileReference file
        ) unique

        Video = (
            DawProjectCore.TimelineHeader header,
            number? sample_rate,
            number? channels,
            string? algorithm,
            number duration,
            DawProjectRoot.FileReference file
        ) unique

        Warps = (
            DawProjectCore.TimelineHeader header,
            DawProjectCore.TimeUnit content_time_unit,
            DawProjectTimeline.Warp* warps,
            DawProjectTimeline.TimelineContent content
        ) unique

        Warp = (number time, number content_time) unique

        Markers = (
            DawProjectCore.TimelineHeader header,
            DawProjectTimeline.Marker* markers
        ) unique

        Marker = (DawProjectCore.Nameable meta, number time) unique
    }

    module DawProjectRoot {
        MetaData = (
            string? title,
            string? artist,
            string? album,
            string? original_artist,
            string? composer,
            string? songwriter,
            string? producer,
            string? arranger,
            string? year,
            string? genre,
            string? copyright,
            string? website,
            string? comment
        ) unique

        Application = (string name, string version) unique
        FileReference = (string path, boolean? external) unique

        Transport = (
            DawProjectParams.RealParameter? tempo,
            DawProjectParams.TimeSignatureParameter? time_signature
        ) unique

        MixerNode = TrackNode(DawProjectMixer.Track track)
                  | ChannelNode(DawProjectMixer.Channel channel)

        Project = (
            string version,
            DawProjectRoot.Application application,
            DawProjectRoot.Transport? transport,
            DawProjectRoot.MixerNode* structure,
            DawProjectTimeline.Arrangement? arrangement,
            DawProjectTimeline.Scene* scenes
        ) unique
    }

    module DawProjectNormalizedCore {
        Nameable = (
            string? name,
            string? color,
            string? comment
        ) unique

        RefHeader = (
            string? id,
            DawProjectNormalizedCore.Nameable meta
        ) unique

        TimelineScope = (
            string? track,
            DawProjectCore.TimeUnit time_unit
        ) unique

        TimelineHeader = (
            string? id,
            string? name,
            string? color,
            string? comment,
            DawProjectNormalizedCore.TimelineScope scope
        ) unique

        ParameterHeader = (
            string? id,
            string? name,
            string? color,
            string? comment,
            number? parameter_id
        ) unique

        TrackHeader = (
            string? id,
            string? name,
            string? color,
            string? comment,
            DawProjectCore.ContentType* content_type,
            boolean loaded
        ) unique

        ChannelHeader = (
            string? id,
            string? name,
            string? color,
            string? comment,
            DawProjectCore.ChannelRole? role,
            number? audio_channels,
            boolean solo,
            string? destination
        ) unique

        SendHeader = (
            string? id,
            string? name,
            string? color,
            string? comment,
            DawProjectCore.SendType type,
            string? destination
        ) unique

        DeviceHeader = (
            string? id,
            string? name,
            string? color,
            string? comment,
            DawProjectCore.DeviceRole device_role,
            boolean loaded,
            string device_name,
            string? device_id,
            string? device_vendor
        ) unique

        ClipTiming = (number time, number duration) unique

        ClipContentTiming = (
            DawProjectCore.TimeUnit content_time_unit,
            number play_start,
            number play_stop,
            number? loop_start,
            number? loop_end
        ) unique

        ClipFade = (
            DawProjectCore.TimeUnit fade_time_unit,
            number? fade_in_time,
            number? fade_out_time
        ) unique

        PluginState = EmbeddedState(DawProjectRoot.FileReference file)
                    | NoState
    }

    module DawProjectNormalizedParams {
        Parameter = BoolParam(DawProjectNormalizedParams.BoolParameter value)
                  | EnumParam(DawProjectNormalizedParams.EnumParameter value)
                  | IntegerParam(DawProjectNormalizedParams.IntegerParameter value)
                  | RealParam(DawProjectNormalizedParams.RealParameter value)
                  | TimeSignatureParam(DawProjectNormalizedParams.TimeSignatureParameter value)

        BoolParameter = (DawProjectNormalizedCore.ParameterHeader header, boolean? value) unique
        EnumParameter = (DawProjectNormalizedCore.ParameterHeader header, number count, number? value, string* labels) unique
        IntegerParameter = (DawProjectNormalizedCore.ParameterHeader header, number? min, number? max, number? value) unique
        RealParameter = (DawProjectNormalizedCore.ParameterHeader header, DawProjectCore.RealUnit unit, number? min, number? max, number? value) unique
        TimeSignatureParameter = (DawProjectNormalizedCore.ParameterHeader header, number numerator, number denominator) unique
    }

    module DawProjectNormalizedAutomation {
        Points = BoolPoints(DawProjectNormalizedAutomation.PointsHeader header,
                            DawProjectNormalizedAutomation.AutomationTarget target,
                            DawProjectNormalizedAutomation.BoolPoint* points)
               | EnumPoints(DawProjectNormalizedAutomation.PointsHeader header,
                            DawProjectNormalizedAutomation.AutomationTarget target,
                            DawProjectNormalizedAutomation.EnumPoint* points)
               | IntegerPoints(DawProjectNormalizedAutomation.PointsHeader header,
                               DawProjectNormalizedAutomation.AutomationTarget target,
                               DawProjectNormalizedAutomation.IntegerPoint* points)
               | RealPoints(DawProjectNormalizedAutomation.PointsHeader header,
                            DawProjectNormalizedAutomation.AutomationTarget target,
                            DawProjectCore.RealUnit unit,
                            DawProjectNormalizedAutomation.RealPoint* points)
               | TimeSignaturePoints(DawProjectNormalizedAutomation.PointsHeader header,
                                      DawProjectNormalizedAutomation.AutomationTarget target,
                                      DawProjectNormalizedAutomation.TimeSignaturePoint* points)

        PointsHeader = (DawProjectNormalizedCore.TimelineHeader header) unique

        AutomationTarget = ParameterTarget(string parameter)
                         | ExpressionTarget(DawProjectCore.ExpressionType expression,
                                            number? channel,
                                            number? key,
                                            number? controller)

        BoolPoint = (number time, boolean value) unique
        EnumPoint = (number time, number value) unique
        IntegerPoint = (number time, number value) unique
        RealPoint = (number time, number value, DawProjectCore.Interpolation interpolation) unique
        TimeSignaturePoint = (number time, number numerator, number denominator) unique
    }

    module DawProjectNormalizedDevices {
        Device = PluginNode(DawProjectNormalizedDevices.PluginDevice device)
               | BuiltinNode(DawProjectNormalizedDevices.BuiltinDevice device)
               | CompressorNode(DawProjectNormalizedDevices.Compressor device)
               | EqualizerNode(DawProjectNormalizedDevices.Equalizer device)
               | LimiterNode(DawProjectNormalizedDevices.Limiter device)
               | NoiseGateNode(DawProjectNormalizedDevices.NoiseGate device)

        PluginDevice = (
            DawProjectNormalizedCore.DeviceHeader header,
            DawProjectCore.PluginFormat format,
            string? plugin_version,
            DawProjectNormalizedParams.BoolParameter? enabled,
            DawProjectNormalizedCore.PluginState state,
            DawProjectNormalizedParams.Parameter* parameters
        ) unique

        BuiltinDevice = (
            DawProjectNormalizedCore.DeviceHeader header,
            DawProjectNormalizedParams.BoolParameter? enabled,
            DawProjectNormalizedCore.PluginState state,
            DawProjectNormalizedParams.Parameter* extra_parameters
        ) unique

        Compressor = (
            DawProjectNormalizedDevices.BuiltinDevice base,
            DawProjectNormalizedParams.RealParameter? threshold,
            DawProjectNormalizedParams.RealParameter? ratio,
            DawProjectNormalizedParams.RealParameter? attack,
            DawProjectNormalizedParams.RealParameter? release,
            DawProjectNormalizedParams.RealParameter? input_gain,
            DawProjectNormalizedParams.RealParameter? output_gain,
            DawProjectNormalizedParams.BoolParameter? auto_makeup
        ) unique

        Equalizer = (
            DawProjectNormalizedDevices.BuiltinDevice base,
            DawProjectNormalizedDevices.EqBand* bands,
            DawProjectNormalizedParams.RealParameter? input_gain,
            DawProjectNormalizedParams.RealParameter? output_gain
        ) unique

        EqBand = (
            DawProjectCore.EqBandType type,
            number? order,
            DawProjectNormalizedParams.RealParameter freq,
            DawProjectNormalizedParams.RealParameter? gain,
            DawProjectNormalizedParams.RealParameter? q,
            DawProjectNormalizedParams.BoolParameter? enabled
        ) unique

        Limiter = (
            DawProjectNormalizedDevices.BuiltinDevice base,
            DawProjectNormalizedParams.RealParameter? threshold,
            DawProjectNormalizedParams.RealParameter? input_gain,
            DawProjectNormalizedParams.RealParameter? output_gain,
            DawProjectNormalizedParams.RealParameter? attack,
            DawProjectNormalizedParams.RealParameter? release
        ) unique

        NoiseGate = (
            DawProjectNormalizedDevices.BuiltinDevice base,
            DawProjectNormalizedParams.RealParameter? threshold,
            DawProjectNormalizedParams.RealParameter? ratio,
            DawProjectNormalizedParams.RealParameter? attack,
            DawProjectNormalizedParams.RealParameter? release,
            DawProjectNormalizedParams.RealParameter? range
        ) unique
    }

    module DawProjectNormalizedMixer {
        Track = (
            DawProjectNormalizedCore.TrackHeader header,
            DawProjectNormalizedMixer.Channel? channel,
            DawProjectNormalizedMixer.Track* tracks
        ) unique

        Channel = (
            DawProjectNormalizedCore.ChannelHeader header,
            DawProjectNormalizedParams.RealParameter? volume,
            DawProjectNormalizedParams.RealParameter? pan,
            DawProjectNormalizedParams.BoolParameter? mute,
            DawProjectNormalizedMixer.Send* sends,
            DawProjectNormalizedDevices.Device* devices
        ) unique

        Send = (
            DawProjectNormalizedCore.SendHeader header,
            DawProjectNormalizedParams.RealParameter volume,
            DawProjectNormalizedParams.RealParameter? pan,
            DawProjectNormalizedParams.BoolParameter? enable
        ) unique
    }

    module DawProjectNormalizedTimeline {
        Arrangement = (
            DawProjectNormalizedCore.RefHeader header,
            DawProjectNormalizedAutomation.Points? time_signature_automation,
            DawProjectNormalizedAutomation.Points? tempo_automation,
            DawProjectNormalizedTimeline.Markers? markers,
            DawProjectNormalizedTimeline.Lanes? lanes
        ) unique

        Scene = (
            DawProjectNormalizedCore.RefHeader header,
            DawProjectNormalizedTimeline.TimelineNode* content
        ) unique

        TimelineNode = ClipSlotNode(DawProjectNormalizedTimeline.ClipSlot value)
                     | ClipsNode(DawProjectNormalizedTimeline.Clips value)
                     | LanesNode(DawProjectNormalizedTimeline.Lanes value)
                     | NotesNode(DawProjectNormalizedTimeline.Notes value)
                     | AudioNode(DawProjectNormalizedTimeline.Audio value)
                     | VideoNode(DawProjectNormalizedTimeline.Video value)
                     | WarpsNode(DawProjectNormalizedTimeline.Warps value)
                     | MarkersNode(DawProjectNormalizedTimeline.Markers value)
                     | AutomationNode(DawProjectNormalizedAutomation.Points value)

        ClipSlot = (DawProjectNormalizedCore.TimelineHeader header, boolean has_stop, DawProjectNormalizedTimeline.Clip? clip) unique
        Clips = (DawProjectNormalizedCore.TimelineHeader header, DawProjectNormalizedTimeline.Clip* clips) unique
        Lanes = (DawProjectNormalizedCore.TimelineHeader header, DawProjectNormalizedTimeline.TimelineNode* lanes) unique

        Clip = (
            DawProjectNormalizedCore.Nameable meta,
            DawProjectNormalizedCore.ClipTiming timing,
            boolean enabled,
            DawProjectNormalizedCore.ClipContentTiming content_timing,
            DawProjectNormalizedCore.ClipFade fade,
            DawProjectNormalizedTimeline.ClipSource source
        ) unique

        ClipSource = Embedded(DawProjectNormalizedTimeline.TimelineNode content)
                   | Referenced(string reference)

        Notes = (DawProjectNormalizedCore.TimelineHeader header, DawProjectNormalizedTimeline.Note* notes) unique
        Note = (number time, number duration, number? channel, number key, number? vel, number? rel, DawProjectNormalizedTimeline.TimelineNode* expressions) unique

        Audio = (DawProjectNormalizedCore.TimelineHeader header, number sample_rate, number channels, string? algorithm, number duration_seconds, DawProjectRoot.FileReference file) unique
        Video = (DawProjectNormalizedCore.TimelineHeader header, number? sample_rate, number? channels, string? algorithm, number duration_seconds, DawProjectRoot.FileReference file) unique
        Warps = (DawProjectNormalizedCore.TimelineHeader header, DawProjectCore.TimeUnit content_time_unit, DawProjectNormalizedTimeline.Warp* warps, DawProjectNormalizedTimeline.TimelineNode content) unique
        Warp = (number time, number content_time) unique
        Markers = (DawProjectNormalizedCore.TimelineHeader header, DawProjectNormalizedTimeline.Marker* markers) unique
        Marker = (DawProjectNormalizedCore.Nameable meta, number time) unique
    }

    module DawProjectNormalized {
        Transport = (
            DawProjectNormalizedParams.RealParameter? tempo,
            DawProjectNormalizedParams.TimeSignatureParameter? time_signature
        ) unique

        RootNode = TrackNode(DawProjectNormalizedMixer.Track track)
                 | ChannelNode(DawProjectNormalizedMixer.Channel channel)

        Project = (
            string version,
            DawProjectRoot.Application application,
            DawProjectRoot.MetaData? metadata,
            DawProjectNormalized.Transport? transport,
            DawProjectNormalized.RootNode* structure,
            DawProjectNormalizedTimeline.Arrangement? arrangement,
            DawProjectNormalizedTimeline.Scene* scenes
        ) unique
    }

    module DemoView {
        TransportButton = (string id, string label, boolean active)

        TitleBar = (
            string app_badge,
            string document_title,
            string engine_text
        )

        TransportBar = (
            string phase_verb,
            string bpm_text,
            string meter_text,
            string clock_text,
            DemoView.TransportButton* buttons
        )

        BrowserRail = (
            string title,
            string subtitle,
            string empty_message
        )

        LauncherButton = (
            string id,
            string label,
            boolean active
        )

        LauncherSlot = (
            string id,
            string label,
            boolean active
        )

        LauncherTrackRow = (
            number index,
            string id,
            string icon,
            string title,
            string subtitle,
            string meter_text,
            DemoView.LauncherButton* buttons,
            DemoView.LauncherSlot* slots,
            boolean active
        )

        LauncherPanel = (
            string title,
            string scene_title_a,
            string scene_title_b,
            DemoView.LauncherTrackRow* rows
        )

        ArrangementTrackRow = (
            number index,
            string id,
            string title,
            string subtitle,
            string route,
            boolean active
        )

        ArrangementClip = (
            number index,
            string id,
            number track_index,
            string label,
            number start_beat,
            number length_beat,
            number color,
            boolean warped,
            boolean active
        )

        ArrangementPanel = (
            string title,
            string note,
            string overlay_mode,
            number beat_count,
            DemoView.ArrangementTrackRow* tracks,
            DemoView.ArrangementClip* clips
        )

        InspectorField = ValueField(
                             string label,
                             string value,
                             boolean active)
                       | ToggleField(
                             string label,
                             boolean value,
                             boolean active)
                       | ChoiceField(
                             string label,
                             string value,
                             string* choices,
                             boolean active)

        InspectorSection = (
            string title,
            DemoView.InspectorField* fields
        )

        InspectorPanel = (
            string title,
            DemoView.InspectorSection* sections
        )

        DeviceCard = (
            number index,
            string id,
            string name,
            string family,
            boolean active
        )

        DevicesPanel = (
            string title,
            string current_track_name,
            string current_phase_name,
            DemoView.DeviceCard* devices
        )

        RemotePanel = (
            string title,
            string subtitle,
            string empty_message
        )

        StatusBar = (
            string left,
            string right
        )

        Window = (
            DemoView.TitleBar titlebar,
            DemoView.TransportBar transport,
            DemoView.BrowserRail browser_rail,
            DemoView.LauncherPanel launcher,
            DemoView.ArrangementPanel arrangement,
            DemoView.InspectorPanel inspector,
            DemoView.DevicesPanel devices,
            DemoView.RemotePanel remote,
            DemoView.StatusBar status
        )
    }

    module Demo {
        Phase = (
            string key,
            string title,
            string verb,
            string consumes,
            string summary
        ) unique

        State = (
            number rev,
            number time,
            boolean playing,
            string selected_view,
            number selected_phase,
            number selected_track,
            number compile_gen,
            number transport_beat,
            number bpm,
            number cpu_usage,
            number semantic_reuse,
            number terra_reuse,
            number structural_edits,
            number live_edits,
            string last_compile_kind,
            number* gains_db,
            number* pans,
            Demo.Phase* phases,
            DawProjectNormalized.Project project,
            string* armed_tracks,
            string* launched_slots,
            string* logs
        )
    }
]]

local Demo = T.Demo
local DemoView = T.DemoView
local NProject = T.DawProjectNormalized
local NMixer = T.DawProjectNormalizedMixer
local NDevices = T.DawProjectNormalizedDevices
local NTimeline = T.DawProjectNormalizedTimeline

local function append_all(out, seq)
    for i = 1, #seq do
        out[#out + 1] = seq[i]
    end
    return out
end

local function collect_track_tree(track, out)
    out[#out + 1] = track
    for i = 1, #track.tracks do
        collect_track_tree(track.tracks[i], out)
    end
end

local append_timeline_node
local append_timeline_lanes

append_timeline_lanes = function(lanes, track_id, out)
    for i = 1, #lanes.lanes do
        append_timeline_node(lanes.lanes[i], track_id, out)
    end
end

append_timeline_node = function(node, track_id, out)
    local kind = node.kind
    if kind == "ClipSlotNode" then
        local slot = node.value
        if slot.clip and slot.header.scope.track == track_id then
            out[#out + 1] = slot.clip
        end
    elseif kind == "ClipsNode" then
        local clips = node.value
        if clips.header.scope.track == track_id then
            append_all(out, clips.clips)
        end
    elseif kind == "LanesNode" then
        append_timeline_lanes(node.value, track_id, out)
    end
end

function NProject.Project:tracks_flat()
    local out = {}
    for i = 1, #self.structure do
        local node = self.structure[i]
        if node.kind == "TrackNode" then
            collect_track_tree(node.track, out)
        end
    end
    return out
end

function NProject.Project:track_at(index)
    return self:tracks_flat()[index]
end

function NProject.Project:clips_for_track(track_or_id)
    local track_id = type(track_or_id) == "string" and track_or_id
        or (track_or_id and track_or_id.header and track_or_id.header.id)
    local out = {}
    if not track_id then
        return out
    end
    if self.arrangement and self.arrangement.lanes then
        append_timeline_lanes(self.arrangement.lanes, track_id, out)
    end
    return out
end

function NMixer.Track:track_id()
    return self.header.id
end

function NMixer.Track:display_name()
    return self.header.name or self.header.id or "Track"
end

function NMixer.Track:display_role()
    local channel = self.channel
    if channel and channel.header.role then
        local kind = channel.header.role.kind
        if kind == "Effect" then return "return" end
        if kind == "Master" or kind == "Submix" or kind == "VCA" then return "group" end
    end
    for i = 1, #self.header.content_type do
        local kind = self.header.content_type[i].kind
        if kind == "NotesContent" then return "instrument" end
        if kind == "AudioContent" then return "audio" end
    end
    return "track"
end

function NMixer.Track:destination_name()
    return (self.channel and self.channel.header.destination) or "Master"
end

function NMixer.Track:device_chain()
    return (self.channel and self.channel.devices) or {}
end

function NMixer.Track:send_chain()
    return (self.channel and self.channel.sends) or {}
end

function NMixer.Track:is_loaded()
    return self.header.loaded
end

function NDevices.Device:header()
    if self.kind == "PluginNode" or self.kind == "BuiltinNode" then
        return self.device.header
    end
    return self.device.base.header
end

function NDevices.Device:display_name()
    local header = self:header()
    return header.name or header.device_name or header.id or "Device"
end

function NDevices.Device:family_name()
    if self.kind == "PluginNode" then
        return self.device.format.kind
    end
    return self:header().device_role.kind
end

function NDevices.Device:is_active()
    local enabled
    if self.kind == "PluginNode" or self.kind == "BuiltinNode" then
        enabled = self.device.enabled
    else
        enabled = self.device.base.enabled
    end
    return enabled == nil or enabled.value ~= false
end

function NTimeline.Clip:display_name()
    return self.meta.name or (self.source.kind == "Referenced" and self.source.reference) or "Clip"
end

function NTimeline.Clip:start_beat()
    return self.timing.time
end

function NTimeline.Clip:length_beat()
    return self.timing.duration
end

function NTimeline.Clip:display_color()
    return self.meta.color
end

function NTimeline.Clip:is_warped()
    return self.source.kind == "Embedded" and self.source.content.kind == "WarpsNode"
end

function Demo.State:tracks()
    return self.project:tracks_flat()
end

function Demo.State:current_phase()
    return self.phases[self.selected_phase]
end

function Demo.State:current_track()
    local tracks = self:tracks()
    local index = self.selected_track
    if index < 1 then index = 1 end
    if index > #tracks then index = #tracks end
    return tracks[index]
end

function Demo.State:clips_for_track(track)
    return self.project:clips_for_track(track)
end

function Demo.State:is_track_armed(track_id)
    for i = 1, #self.armed_tracks do
        if self.armed_tracks[i] == track_id then
            return true
        end
    end
    return false
end

function Demo.State:is_slot_launched(slot_id)
    for i = 1, #self.launched_slots do
        if self.launched_slots[i] == slot_id then
            return true
        end
    end
    return false
end

return M
