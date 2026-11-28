package browserloop

import (
 "encoding/json"
 "strings"
 "testing"
)

func TestPolicyProjection(t *testing.T) {
 cfg:=`{"proxies":[{"name":"node","type":"http","server":"proxy.example","port":80}],"rules":["DOMAIN,example.com,REJECT","IP-CIDR,203.0.113.0/24,BROWSER-PROXY,no-resolve","IP-CIDR6,2001:db8::/32,DIRECT,no-resolve","MATCH,REJECT"]}`
 data,err:=project(cfg,t.TempDir());if err!=nil{t.Fatal(err)}
 var result struct{ Rules []string }
 if json.Unmarshal(data,&result)!=nil||len(result.Rules)!=4||result.Rules[0]!="DOMAIN,example.com,REJECT"{t.Fatal("custom rules lost")}
 for _,bad:=range []string{"IP-CIDR,2001:db8::/32,DIRECT,no-resolve","IP-CIDR,203.0.113.0/24,DIRECT","IP-CIDR6,2001:db8::/129,DIRECT,no-resolve","RULE-SET,remote,DIRECT"} {
  if _,err:=project(strings.Replace(cfg,"IP-CIDR,203.0.113.0/24,BROWSER-PROXY,no-resolve",bad,1),t.TempDir());err==nil{t.Fatal("invalid custom rule accepted",bad)}
 }
 rules:=globalRules([]string{"DOMAIN,example.com,DIRECT"},true)
 if rules[0]!="DOMAIN,example.com,DIRECT"||rules[1]!="RULE-SET,builtin-reject,REJECT"||rules[len(rules)-1]!="MATCH,BROWSER-PROXY"{t.Fatal(rules)}
 for _,r:=range rules {if strings.Contains(r,"builtin-direct")||strings.Contains(r,"builtin-cncidr"){t.Fatal("global mode contains domestic direct list")}}
}
