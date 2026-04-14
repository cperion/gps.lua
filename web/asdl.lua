local M = {}

function M.Define(T)
    T:Define [[
        module Html {
            Node = Doc(string doctype, Html.Node root) unique
                 | El(string tag, string? key, Html.Attr* attrs, Html.Node* children) unique
                 | Text(string content) unique
                 | Raw(string html) unique
                 | Fragment(Html.Node* children) unique
                 | Empty unique

            Attr = Str(string name, string value) unique
                 | Bool(string name) unique
        }

        module Patch {
            Seg = Key(string key) unique
            Path = (Patch.Seg* segs) unique

            Op = Replace(Patch.Path path, Html.Node node) unique
               | Remove(Patch.Path path) unique
               | Append(Patch.Path path, Html.Node node) unique
               | SetAttr(Patch.Path path, string name, string? value) unique
               | RemoveAttr(Patch.Path path, string name) unique
               | SetText(Patch.Path path, string text) unique

            Batch = (Patch.Op* ops) unique
        }
    ]]
    return T
end

return M
