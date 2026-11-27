package browserloop

import (
 "crypto/sha256"
 "encoding/hex"
 "encoding/json"
 "errors"
 "os"
 "path/filepath"
 "regexp"
)

var ruleBehaviors = map[string]string{
 "reject":"domain", "private":"domain", "icloud":"domain", "apple":"domain",
 "google":"domain", "proxy":"domain", "direct":"domain",
 "lancidr":"ipcidr", "cncidr":"ipcidr", "telegramcidr":"ipcidr",
}
var gitRevision = regexp.MustCompile("^[a-f0-9]{40}$")

// Only app-bundled files, staged in the new private session directory.
// This is integrity validation of trusted installation assets, not a remote
// signature protocol. Downloaded rules must not use this entry point yet.
func builtinProviders(home string) (map[string]any, error) {
 dir:=filepath.Join(home,"rules")
 var manifest struct { Revision string; Files map[string]string }
 bytes,err:=os.ReadFile(filepath.Join(dir,"manifest.json"))
 if err!=nil || json.Unmarshal(bytes,&manifest)!=nil ||
    !gitRevision.MatchString(manifest.Revision) || len(manifest.Files)!=len(ruleBehaviors) {
  return nil,errors.New("invalid builtin manifest")
 }
 providers:=map[string]any{}
 for name,behavior:=range ruleBehaviors {
  file:=name+".mrs"
  content,err:=os.ReadFile(filepath.Join(dir,file))
  if err!=nil || len(content)==0 {return nil,errors.New("missing builtin rules")}
  sum:=sha256.Sum256(content)
  if hex.EncodeToString(sum[:])!=manifest.Files[file] {return nil,errors.New("builtin rules integrity failed")}
  providers["builtin-"+name]=map[string]any{
   "type":"file","behavior":behavior,"format":"mrs",
   "path":filepath.Join("rules",file),
  }
 }
 return providers,nil
}

func smartRules(custom []string, adBlock bool) []string {
 // Custom rules have explicit priority. Private-network support is staged
 // separately; this phase does not change the native WebView URL gates.
 rules:=append([]string{},custom...)
 if adBlock {rules=append(rules,"RULE-SET,builtin-reject,REJECT")}
 return append(rules,
  "RULE-SET,builtin-private,REJECT",
  "RULE-SET,builtin-lancidr,REJECT,no-resolve",
  "RULE-SET,builtin-icloud,DIRECT",
  "RULE-SET,builtin-apple,DIRECT",
  "RULE-SET,builtin-google,BROWSER-PROXY",
  "RULE-SET,builtin-proxy,BROWSER-PROXY",
  "RULE-SET,builtin-direct,DIRECT",
  "RULE-SET,builtin-cncidr,DIRECT,no-resolve",
  "RULE-SET,builtin-telegramcidr,BROWSER-PROXY,no-resolve",
  "MATCH,BROWSER-PROXY")
}
