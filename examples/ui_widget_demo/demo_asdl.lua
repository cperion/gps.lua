local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T

T:Define [[
    module Widget {
        ThemeMode = ThemeDark | ThemeLight

        Section = Buttons
                | Toggles
                | TextInputs
                | Sliders
                | ProgressBars
                | Badges
                | Cards
                | Alerts
                | Tabs
                | Avatars
                | Tooltips

        ToggleState = On | Off

        TabKind = Home | Profile | Settings | Notifications

        AlertTone = AlertInfo | AlertSuccess | AlertWarning | AlertError

        BadgeTone = BadgeDefault | BadgePrimary | BadgeSuccess | BadgeWarning | BadgeError

        SliderItem = (string label,
                      number value) unique

        ToggleItem = (string label,
                      Widget.ToggleState state) unique

        TextInputItem = (string label,
                         string placeholder,
                         string value) unique

        ProgressItem = (string label,
                        number fraction) unique

        BadgeItem = (string label,
                     Widget.BadgeTone tone) unique

        AlertItem = (string title,
                     string body,
                     Widget.AlertTone tone) unique

        CardItem = (string title,
                    string body,
                    string meta) unique

        AvatarItem = (string initials,
                      number hue) unique

        TooltipItem = (string label,
                       string tip) unique

        App = (Widget.ThemeMode theme_mode,
               Widget.Section section,
               Widget.TabKind tab,
               Widget.ToggleItem* toggles,
               Widget.SliderItem* sliders,
               Widget.TextInputItem* text_inputs,
               Widget.ProgressItem* progresses,
               Widget.BadgeItem* badges,
               Widget.AlertItem* alerts,
               Widget.CardItem* cards,
               Widget.AvatarItem* avatars,
               Widget.TooltipItem* tooltips,
               number tick) unique

        State = (Widget.App app,
                 Interact.Model ui_model) unique

        Event = SetSection(Widget.Section section) unique
              | SetTab(Widget.TabKind tab) unique
              | ToggleTheme unique
              | FlipToggle(number index) unique
              | SlideTo(number index, number value) unique
              | EditText(number index, string value) unique
              | Tick unique
    }
]]

return {
    T = T,
}
