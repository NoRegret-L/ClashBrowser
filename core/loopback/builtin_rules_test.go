package browserloop

import (
 "encoding/json"
 "fmt"
 "io"
 "net/http"
 "net/http/httptest"
 "net/url"
 "os"
 "path/filepath"
 "strings"
 "testing"
 "time"
)

func TestSmartRuleOrder(t *testing.T) {
 custom:=[]string{"DOMAIN-SUFFIX,example.com,DIRECT"}
 rules:=smartRules(custom,true)
 if rules[0]!=custom[0]||rules[1]!="RULE-SET,builtin-reject,REJECT"||rules[len(rules)-1]!="MATCH,BROWSER-PROXY"{t.Fatal(rules)}
 for _,r:=range smartRules(custom,false) {if strings.Contains(r,"builtin-reject"){t.Fatal("ad switch ignored")}}
 for _,name:=range []string{"lancidr","cncidr","telegramcidr"} {
  found:=false
  for _,r:=range rules {if strings.Contains(r,"builtin-"+name+","){found=strings.HasSuffix(r,",no-resolve")}}
  if !found{t.Fatal("IP rule must not trigger resolution",name)}
 }
}

func TestBuiltinSnapshot(t *testing.T) {
 source:=os.Getenv("CLASHBROWSER_RULE_BUNDLE")
 if source==""{t.Skip("generated snapshot not available; required in host CI")}
 home:=t.TempDir()
 dir:=filepath.Join(home,"rules")
 if err:=os.Mkdir(dir,0700);err!=nil{t.Fatal(err)}
 for _,name:=range append([]string{"manifest.json"},func()[]string{var a []string;for n:=range ruleBehaviors{a=append(a,n+".mrs")};return a}()...) {
  bytes,err:=os.ReadFile(filepath.Join(source,name));if err!=nil{t.Fatal(err)}
  if err=os.WriteFile(filepath.Join(dir,name),bytes,0600);err!=nil{t.Fatal(err)}
 }
 upstream:=httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){
  if r.Method!=http.MethodConnect||r.Host!="clashbrowser-unlisted-probe.invalid:80"{t.Error("unexpected upstream target");w.WriteHeader(400);return}
  conn,rw,err:=w.(http.Hijacker).Hijack();if err!=nil{t.Error(err);return};defer conn.Close()
  fmt.Fprint(rw,"HTTP/1.1 200 OK\r\n\r\n");rw.Flush()
  req,err:=http.ReadRequest(rw.Reader);if err!=nil{return};req.Body.Close()
  fmt.Fprint(rw,"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok");rw.Flush()
 }))
 defer upstream.Close()
 u,_:=url.Parse(upstream.URL)
 cfg:=fmt.Sprintf("{\"routingMode\":\"smart\",\"proxies\":[{\"name\":\"test\",\"type\":\"http\",\"server\":%q,\"port\":%s}],\"rules\":[\"MATCH,REJECT\"]}",u.Hostname(),u.Port())
 call:=func(action,config string)map[string]any{
  data,_:=json.Marshal(map[string]string{"action":action,"configJson":config,"homeDir":home})
  var res map[string]any
  if json.Unmarshal([]byte(Command(string(data))),&res)!=nil{t.Fatal("invalid native reply")}
  return res
 }
 res:=call("start",cfg);if res["ready"]!=true{t.Fatal("smart mode failed to load snapshot",res)}
 defer call("stop","")
 p,_:=url.Parse(fmt.Sprintf("http://127.0.0.1:%.0f",res["port"]))
 p.User=url.UserPassword(res["username"].(string),res["password"].(string))
 transport:=&http.Transport{Proxy:http.ProxyURL(p)};defer transport.CloseIdleConnections()
 client:=&http.Client{Transport:transport,Timeout:5*time.Second}
 response,err:=client.Get("http://clashbrowser-unlisted-probe.invalid/")
 if err!=nil{t.Fatal(err)}
 body,_:=io.ReadAll(response.Body);response.Body.Close()
 if response.StatusCode!=200||string(body)!="ok"{t.Fatal("unmatched request did not use selected proxy")}
 if call("stop","")["stopped"]!=true{t.Fatal("stop failed")}
 if err:=os.WriteFile(filepath.Join(dir,"reject.mrs"),[]byte("corrupt"),0600);err!=nil{t.Fatal(err)}
 if call("start",cfg)["ready"]!=false{t.Fatal("corrupt rules accepted")}
}
