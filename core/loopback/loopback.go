// Package browserloop embeds Mihomo's HTTP protocol handler without a VPN.
package browserloop

import (
 "crypto/rand"
 "encoding/hex"
 "encoding/json"
 "errors"
 "net"
 "os"
 "path/filepath"
 "regexp"
 "strconv"
 "strings"
 "sync"

 "github.com/metacubex/mihomo/adapter/inbound"
 "github.com/metacubex/mihomo/component/auth"
 C "github.com/metacubex/mihomo/constant"
 "github.com/metacubex/mihomo/hub/executor"
 authstore "github.com/metacubex/mihomo/listener/auth"
 proxyhttp "github.com/metacubex/mihomo/listener/http"
 "github.com/metacubex/mihomo/tunnel"
)

var lifecycle sync.Mutex
var active *session
var domain = regexp.MustCompile("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$")
var protocols = map[string]string{
 "http":"username password", "socks5":"username password",
 "ss":"cipher password", "trojan":"password network ws-opts",
 "vmess":"uuid alterId cipher network ws-opts",
 "vless":"uuid flow network ws-opts reality-opts",
}

type session struct {
 listener net.Listener
 mu sync.Mutex
 closed bool
 clients map[*tracked]struct{}
}
type tracked struct { net.Conn; owner *session; once sync.Once }
func (c *tracked) Close() error {
 var err error
 c.once.Do(func(){ err=c.Conn.Close(); c.owner.mu.Lock(); delete(c.owner.clients,c); c.owner.mu.Unlock() })
 return err
}
func (s *session) serve(store auth.AuthStore) {
 for {
  conn,err:=s.listener.Accept()
  if err!=nil {return}
  s.mu.Lock()
  if s.closed {s.mu.Unlock(); conn.Close(); return}
  client:=&tracked{Conn:conn,owner:s}
  s.clients[client]=struct{}{}
  s.mu.Unlock()
  // CONNECT transfers ownership to Mihomo; close on session shutdown, not handler return.
  go proxyhttp.HandleConn(client,tunnel.Tunnel,store,inbound.WithInName("CLASHBROWSER"),inbound.WithSpecialRules(""))
 }
}
func (s *session) close() error {
 s.mu.Lock()
 s.closed=true
 clients:=make([]*tracked,0,len(s.clients))
 for c:=range s.clients {clients=append(clients,c)}
 s.mu.Unlock()
 err:=s.listener.Close()
 for _,c:=range clients {c.Close()}
 return err
}

// Rebuild the configuration at the native trust boundary. No arbitrary top-level
// settings or custom listeners, script, provider, interface or dialer options.
func project(text string) ([]byte,error) {
 var raw struct { Proxies []map[string]any; Rules []string }
 if json.Unmarshal([]byte(text),&raw)!=nil || len(raw.Proxies)!=1 {return nil,errors.New("invalid projection")}
 n:=raw.Proxies[0]
 name,ok:=n["name"].(string)
 if !ok || strings.TrimSpace(name)=="" || strings.ContainsAny(name,",\r\n\x00") {return nil,errors.New("invalid name")}
 switch strings.ToUpper(name) {case "DIRECT","REJECT","REJECT-DROP","PASS","COMPATIBLE","GLOBAL","BROWSER-PROXY":return nil,errors.New("reserved name")}
 typ,_:=n["type"].(string)
 fields,ok:=protocols[typ]; if !ok {return nil,errors.New("unsupported protocol")}
 allowed:=map[string]bool{}
 for _,k:=range strings.Fields("name type server port udp tls servername sni skip-cert-verify client-fingerprint "+fields){allowed[k]=true}
 for k,v:=range n {
  if !allowed[k] {return nil,errors.New("unsupported node field")}
  switch k {
  case "skip-cert-verify":if v!=false{return nil,errors.New("unsafe tls")}
  case "udp","tls":if _,ok:=v.(bool);!ok{return nil,errors.New("invalid boolean")}
  case "port","alterId":if p,ok:=v.(float64);!ok||p!=float64(int(p)){return nil,errors.New("invalid number")}
  case "ws-opts","reality-opts":
   m,ok:=v.(map[string]any);if !ok{return nil,errors.New("invalid transport")}
   for key,val:=range m {
    if k=="ws-opts"&&key=="headers" {
     h,ok:=val.(map[string]any);if !ok{return nil,errors.New("invalid headers")}
     for _,v:=range h{if _,ok:=v.(string);!ok{return nil,errors.New("invalid header")}}
    } else {
     if !(k=="ws-opts"&&key=="path"||k=="reality-opts"&&(key=="public-key"||key=="short-id")){return nil,errors.New("unsupported transport field")}
     if _,ok:=val.(string);!ok{return nil,errors.New("invalid transport field")}
    }
   }
  default:if _,ok:=v.(string);!ok{return nil,errors.New("invalid node field")}
  }
 }
 host,ok:=n["server"].(string);if !ok||host==""||strings.ContainsAny(host," \t\r\n/\\"){return nil,errors.New("invalid server")}
 port,ok:=n["port"].(float64);if !ok||port<1||port>65535{return nil,errors.New("invalid port")}
 if v,ok:=n["network"];ok&&v!="tcp"&&v!="ws"{return nil,errors.New("unsupported transport")}
 if len(raw.Rules)==0||raw.Rules[len(raw.Rules)-1]!="MATCH,REJECT"{return nil,errors.New("missing reject default")}
 for _,r:=range raw.Rules[:len(raw.Rules)-1] {
  p:=strings.Split(r,",");if len(p)!=3||p[0]!="DOMAIN-SUFFIX"||len(p[1])>253||!domain.MatchString(p[1])||(p[2]!="DIRECT"&&p[2]!="BROWSER-PROXY"){return nil,errors.New("invalid rule")}
 }
 return json.Marshal(map[string]any{
  "allow-lan":false,"bind-address":"127.0.0.1","mode":"rule",
  "log-level":"silent","find-process-mode":"off","tun":map[string]any{"enable":false,"auto-route":false,"auto-redirect":false},
  "dns":map[string]any{"enable":false},"geo-auto-update":false,
  "profile":map[string]any{"store-selected":false,"store-fake-ip":false},
  "proxies":[]any{n},"proxy-groups":[]any{map[string]any{"name":"BROWSER-PROXY","type":"select","proxies":[]string{name}}},
  "rules":raw.Rules,
 })
}

type request struct { Action string; ConfigJson string; HomeDir string }
func reply(v map[string]any) string { b,_:=json.Marshal(v);return string(b) }
func failure() string {return reply(map[string]any{"ready":false,"error":"native operation failed"})}

// Command is deliberately limited to start/stop; never logs input or credentials.
func Command(input string)(out string) {
 lifecycle.Lock();defer lifecycle.Unlock()
 var pending *session
 defer func(){if recover()!=nil {if pending!=nil{pending.close()};if active!=nil{active.close();active=nil};tunnel.OnSuspend();out=failure()}}()
 var r request
 if json.Unmarshal([]byte(input),&r)!=nil{return failure()}
 switch r.Action {
 case "stop":
  if active!=nil {s:=active;active=nil;err:=s.close();tunnel.OnSuspend();if err!=nil{return failure()}}
  return reply(map[string]any{"stopped":true})
 case "start":
  if active!=nil || !filepath.IsAbs(r.HomeDir){return failure()}
  cfgBytes,err:=project(r.ConfigJson);if err!=nil{return failure()}
  if err=os.MkdirAll(r.HomeDir,0700);err!=nil{return failure()}
  C.SetHomeDir(r.HomeDir)
  cfg,err:=executor.ParseWithBytes(cfgBytes);if err!=nil||cfg.General.Tun.Enable{return failure()}
  secret:=make([]byte,32);if _,err=rand.Read(secret);err!=nil{return failure()}
  password:=hex.EncodeToString(secret)
  listener,err:=net.Listen("tcp4","127.0.0.1:0");if err!=nil{return failure()}
  pending=&session{listener:listener,clients:map[*tracked]struct{}{}}
  _,portText,err:=net.SplitHostPort(listener.Addr().String());if err!=nil{pending.close();return failure()}
  port,err:=strconv.Atoi(portText);if err!=nil{pending.close();return failure()}
  // No imported listening ports, TUN, external controller, or VPN setup.
  executor.ApplyConfig(cfg,true)
  store:=authstore.NewAuthStore(auth.NewAuthenticator([]auth.AuthUser{{User:"browser",Pass:password}}))
  active=pending;pending=nil
  go active.serve(store)
  return reply(map[string]any{"ready":true,"host":"127.0.0.1","port":port,"tunEnabled":false,"username":"browser","password":password})
 default:return failure()
 }
}
