package browserloop

import (
 "strings"
 "sync"
 C "github.com/metacubex/mihomo/constant"
)

// Bounded in-memory diagnostic history, not persisted browsing history.
// One record per match, including REJECT and connections that end immediately.
// 256 is a resource limit; it has no effect on routing decisions.
const routeHistoryCapacity=256
type routeMatch struct {
 Host string `json:"-"`
 Rule string `json:"rule"`
 Payload string `json:"payload"`
 Policy string `json:"policy"`
}
type routeHistory struct {
 mu sync.Mutex
 records [routeHistoryCapacity]routeMatch
 next,count int
}
func (h *routeHistory) add(m routeMatch) {
 h.mu.Lock();defer h.mu.Unlock()
 h.records[h.next]=m
 h.next=(h.next+1)%len(h.records)
 if h.count<len(h.records){h.count++}
}
func (h *routeHistory) observe(inbound string, metadata *C.Metadata, proxy C.Proxy, rule C.Rule) {
 if metadata.InName!=inbound{return}
 host:=strings.ToLower(metadata.Host)
 if len(host)>253||!domain.MatchString(host){return}
 policy:=proxy.Name()
 if policy!="DIRECT"&&policy!="REJECT"&&policy!="BROWSER-PROXY"{return}
 h.add(routeMatch{Host:host,Rule:rule.RuleType().String(),Payload:rule.Payload(),Policy:policy})
}
func (h *routeHistory) query(host string) []routeMatch {
 h.mu.Lock();defer h.mu.Unlock()
 matches:=[]routeMatch{}
 seen:=map[routeMatch]bool{}
 for i:=0;i<h.count;i++ {
  m:=h.records[(h.next+len(h.records)-1-i)%len(h.records)]
  if m.Host==host&&!seen[m]{seen[m]=true;matches=append(matches,m)}
 }
 return matches
}
func (h *routeHistory) reply(host string) string {
 host=strings.ToLower(host)
 if len(host)>253||!domain.MatchString(host){return failure()}
 matches:=h.query(host)
 return reply(map[string]any{"observed":len(matches)>0,"matches":matches})
}
