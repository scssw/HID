package config

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestParseAnyTLSLink(t *testing.T) {
	link := "anytls://OPzNxfEQjB@txany.ssrr.today:52978?security=tls&sni=txany.ssrr.today#anytls-52978"
	out, err := ParseConfigContent(link, true, nil, false)
	if err != nil {
		t.Fatalf("ParseConfigContent failed: %v", err)
	}

	var parsed map[string]interface{}
	if err := json.Unmarshal(out, &parsed); err != nil {
		t.Fatalf("Failed to unmarshal output: %v", err)
	}

	outbounds, ok := parsed["outbounds"].([]interface{})
	if !ok || len(outbounds) == 0 {
		t.Fatalf("No outbounds in result: %s", string(out))
	}

	found := false
	for _, o := range outbounds {
		om, ok := o.(map[string]interface{})
		if !ok {
			continue
		}
		if om["type"] == "anytls" {
			found = true
			if om["server"] != "txany.ssrr.today" {
				t.Errorf("expected server txany.ssrr.today, got %v", om["server"])
			}
			if om["password"] != "OPzNxfEQjB" {
				t.Errorf("expected password OPzNxfEQjB, got %v", om["password"])
			}
			tlsObj, ok := om["tls"].(map[string]interface{})
			if !ok || tlsObj["server_name"] != "txany.ssrr.today" {
				t.Errorf("expected tls server_name txany.ssrr.today, got %v", om["tls"])
			}
		}
	}
	if !found {
		t.Errorf("anytls outbound not found in output: %s", string(out))
	}
}

func TestParseAnyTLSBase64(t *testing.T) {
	b64 := "YW55dGxzOi8veXl2VWJ0S01ZYUB0eGFueS5zc3JyLnRvZGF5OjUyOTc4P3NlY3VyaXR5PXRscyZzbmk9dHhhbnkuc3Nyci50b2RheSNhbnl0bHMtNTI5Nzg="
	out, err := ParseConfigContent(b64, true, nil, false)
	if err != nil {
		t.Fatalf("ParseConfigContent failed: %v", err)
	}

	if !strings.Contains(string(out), "anytls") {
		t.Errorf("expected anytls in output, got: %s", string(out))
	}
}

func TestParseAnyTLSJson(t *testing.T) {
	jsonContent := `{
  "outbounds": [
    {
      "password": "OPzNxfEQjB",
      "server": "txany.ssrr.today",
      "server_port": 52978,
      "tag": "anytls-52978",
      "tls": {
        "enabled": true,
        "server_name": "txany.ssrr.today"
      },
      "type": "anytls"
    }
  ]
}`
	out, err := ParseConfigContent(jsonContent, true, nil, false)
	if err != nil {
		t.Fatalf("ParseConfigContent failed: %v", err)
	}

	if !strings.Contains(string(out), "anytls-52978") {
		t.Errorf("expected anytls-52978 in output, got: %s", string(out))
	}
}
