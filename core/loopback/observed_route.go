package browserloop

import (
 "strings"
 "github.com/metacubex/mihomo/tunnel/statistic"
)

// Read native live connections, not a second rule engine. Only the requested
// host and browser inbound are considered. No history, URLs, tokens or nodes
// are exposed; completed or rejected flows may have no live observation.
func observedRoute(host string) string {
 host=strings.ToLower(host)
 if len(host)>253||!domain.MatchString(host){return failure()}
 type match struct { Rule string `json:"rule"`; Payload string `json:"payload"` }
 matches:=[]match{}
 seen:=map[match]bool{}
 statistic.DefaultManager.Range(func(c statistic.Tracker)bool{
  info:=c.Info()
  if info==nil||info.Metadata==nil||info.Metadata.InName!="CLASHBROWSER"||!strings.EqualFold(info.Metadata.Host,host)||info.Rule==""{return true}
  m:=match{info.Rule,info.RulePayload}
  if !seen[m]{seen[m]=true;matches=append(matches,m)}
  return true
 })
 return reply(map[string]any{"observed":len(matches)>0,"matches":matches})
}
