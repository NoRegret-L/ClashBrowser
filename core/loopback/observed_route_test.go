package browserloop

import "testing"

func TestRouteHistoryBounded(t *testing.T) {
 var h routeHistory
 h.add(routeMatch{Host:"old.example",Policy:"DIRECT"})
 for i:=0;i<routeHistoryCapacity;i++ {h.add(routeMatch{Host:"new.example",Policy:"REJECT"})}
 if len(h.query("old.example"))!=0 {t.Fatal("evicted record retained")}
 if found:=h.query("new.example");len(found)!=1||found[0].Policy!="REJECT"{t.Fatal(found)}
}
