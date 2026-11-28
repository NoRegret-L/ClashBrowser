package browserloop
import (
 "encoding/json"
 "fmt"
 "io"
 "net/http"
 "net/http/httptest"
 "net/url"
 "strings"
 "testing"
 "time"
)
func TestAuthenticatedLoopback(t *testing.T) {
 upstream:=httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){
  if r.Method!=http.MethodConnect {t.Error("expected CONNECT");w.WriteHeader(400);return}
  conn,rw,err:=w.(http.Hijacker).Hijack();if err!=nil{t.Error(err);return};defer conn.Close()
  fmt.Fprint(rw,"HTTP/1.1 200 OK\r\n\r\n");rw.Flush()
  req,err:=http.ReadRequest(rw.Reader);if err!=nil{return};req.Body.Close()
  fmt.Fprint(rw,"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok");rw.Flush()
 }))
 defer upstream.Close()
 u,_:=url.Parse(upstream.URL)
 cfg:=fmt.Sprintf("{\"proxies\":[{\"name\":\"test\",\"type\":\"http\",\"server\":%q,\"port\":%s}],\"rules\":[\"DOMAIN-SUFFIX,proxied.invalid,BROWSER-PROXY\",\"MATCH,REJECT\"]}",u.Hostname(),u.Port())
 call:=func(action,config string)map[string]any{b,_:=json.Marshal(map[string]string{"action":action,"configJson":config,"homeDir":t.TempDir()});var res map[string]any;if json.Unmarshal([]byte(Command(string(b))),&res)!=nil{t.Fatal("invalid native reply")};return res}
 if call("start",strings.Replace(cfg,"MATCH,REJECT","MATCH,DIRECT",1))["ready"]!=false{t.Fatal("unsafe config accepted")}
 res:=call("start",cfg);if res["ready"]!=true{t.Fatal("start failed")}
 defer call("stop","")
 if call("start",cfg)["ready"]!=false{t.Fatal("duplicate start accepted")}
 address:=fmt.Sprintf("http://127.0.0.1:%.0f",res["port"])
 proxy,_:=url.Parse(address)
 client:=&http.Client{Transport:&http.Transport{Proxy:http.ProxyURL(proxy)},Timeout:5*time.Second}
 response,err:=client.Get("http://proxied.invalid/");if err!=nil{t.Fatal(err)}
 response.Body.Close();if response.StatusCode!=407{t.Fatalf("unauthenticated request: %d",response.StatusCode)}
 proxy.User=url.UserPassword(res["username"].(string),res["password"].(string))
 transport:=&http.Transport{Proxy:http.ProxyURL(proxy)}
 client.Transport=transport;defer transport.CloseIdleConnections()
 response,err=client.Get("http://proxied.invalid/");if err!=nil{t.Fatal(err)}
 body,_:=io.ReadAll(response.Body);response.Body.Close()
 if response.StatusCode!=200||string(body)!="ok"{t.Fatal("proxy routing failed")}
 response,err=client.Get("http://blocked.invalid/");if err==nil{response.Body.Close();if response.StatusCode<400{t.Fatal("default reject failed")}}
 for host,policy:=range map[string]string{"proxied.invalid":"BROWSER-PROXY","blocked.invalid":"REJECT"} {
  b,_:=json.Marshal(map[string]string{"action":"observedRoute","host":host})
  var result struct { Observed bool; Matches []routeMatch }
  if json.Unmarshal([]byte(Command(string(b))),&result)!=nil||!result.Observed||len(result.Matches)==0||result.Matches[0].Policy!=policy {t.Fatalf("missing actual decision for %s: %+v",host,result)}
 }
 if call("stop","")["stopped"]!=true{t.Fatal("stop failed")}
 if res:=call("start",cfg);res["ready"]!=true{t.Fatal("restart failed")}
 var fresh map[string]any
 _=json.Unmarshal([]byte(Command("{\"action\":\"observedRoute\",\"host\":\"proxied.invalid\"}")),&fresh)
 if fresh["observed"]!=false{t.Fatal("previous session observations leaked")}
 if call("stop","")["stopped"]!=true{t.Fatal("second stop failed")}
 transport.CloseIdleConnections()
 if response,err=client.Get("http://proxied.invalid/");err==nil{response.Body.Close();t.Fatal("listener remained open")}
}
