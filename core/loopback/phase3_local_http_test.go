package browserloop

import (
 "encoding/json"
 "fmt"
 "io"
 "net"
 "net/http"
 "net/http/httptest"
 "net/url"
 "testing"
 "time"
)

// The browser remains HTTPS-only. This test verifies the underlying
// authenticated HTTP path using an explicit, test-only DIRECT rule.
func TestPhase3AuthenticatedLoopbackHTTP(t *testing.T) {
 for _, address := range []string{"127.0.0.1:0", "[::1]:0"} {
  t.Run(address, func(t *testing.T) {
   listener, err := net.Listen("tcp", address)
   if err != nil { t.Fatal(err) }
   origin := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
    if r.Header.Get("Proxy-Authorization") != "" || r.Header.Get("Authorization") != "" {
     t.Error("proxy credential reached origin")
     w.WriteHeader(http.StatusBadRequest)
     return
    }
    if r.URL.Path != "/local-probe" { t.Error("unexpected origin request"); w.WriteHeader(400); return }
    _, _ = io.WriteString(w, "local-ok")
   }))
   // NewUnstartedServer allocates its own socket; replace and close that socket.
   _ = origin.Listener.Close()
   origin.Listener = listener
   origin.Start()
   defer origin.Close()
   target, err := url.Parse(origin.URL)
   if err != nil { t.Fatal(err) }
   rule := "IP-CIDR,127.0.0.1/32,DIRECT,no-resolve"
   if target.Hostname() == "::1" { rule = "IP-CIDR6,::1/128,DIRECT,no-resolve" }
   cfg, _ := json.Marshal(map[string]any{
    "proxies": []map[string]any{{"name":"fixture","type":"http","server":"127.0.0.1","port":1}},
    "rules": []string{rule,"MATCH,REJECT"},
   })
   cmd := func(action string) map[string]any {
    b,_ := json.Marshal(map[string]string{"action":action,"configJson":string(cfg),"homeDir":t.TempDir()})
    var result map[string]any
    if err := json.Unmarshal([]byte(Command(string(b))), &result); err != nil { t.Fatal(err) }
    return result
   }
   res := cmd("start")
   if res["ready"] != true { t.Fatal("native listener did not start") }
   defer func(){ if cmd("stop")["stopped"] != true { t.Error("native stop failed") } }()
   proxy, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%.0f",res["port"]))
   transport := &http.Transport{Proxy:http.ProxyURL(proxy)}
   defer transport.CloseIdleConnections()
   client := &http.Client{Transport:transport, Timeout:5*time.Second}
   response, err := client.Get(origin.URL+"/local-probe")
   if err != nil { t.Fatal(err) }
   _ = response.Body.Close()
   if response.StatusCode != http.StatusProxyAuthRequired { t.Fatalf("unauthenticated result: %d", response.StatusCode) }
   proxy.User = url.UserPassword(res["username"].(string),res["password"].(string))
   authenticated := &http.Transport{Proxy:http.ProxyURL(proxy)}
   defer authenticated.CloseIdleConnections()
   client.Transport = authenticated
   response, err = client.Get(origin.URL+"/local-probe")
   if err != nil { t.Fatal(err) }
   body, err := io.ReadAll(response.Body)
   _ = response.Body.Close()
   if err != nil || response.StatusCode != http.StatusOK || string(body) != "local-ok" {
    t.Fatal("authenticated loopback HTTP failed")
   }
  })
 }
}
