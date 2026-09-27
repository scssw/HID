package ray2sing

import (
	"encoding/base64"
	"fmt"
	"strings"

	C "github.com/sagernet/sing-box/constant"
	T "github.com/sagernet/sing-box/option"
	E "github.com/sagernet/sing/common/exceptions"
)

// SSRSingbox parses an ssr:// link and converts it to a ShadowsocksR outbound.
//
// SSR link format:
//
//	ssr://base64(host:port:protocol:method:obfs:base64(password)/?obfsparam=base64(...)&protoparam=base64(...)&remarks=base64(...)&group=base64(...))
func SSRSingbox(ssrUrl string) (*T.Outbound, error) {
	if !strings.HasPrefix(ssrUrl, "ssr://") {
		return nil, E.New("not an SSR URL")
	}
	encoded := strings.TrimPrefix(ssrUrl, "ssr://")
	encoded = strings.TrimSpace(encoded)

	decoded, err := ssrDecodeBase64(encoded)
	if err != nil {
		return nil, E.New("failed to decode SSR base64: ", err)
	}

	mainPart := decoded
	queryPart := ""
	if idx := strings.Index(decoded, "/?"); idx != -1 {
		mainPart = decoded[:idx]
		queryPart = decoded[idx+2:]
	} else if idx := strings.Index(decoded, "?"); idx != -1 {
		mainPart = decoded[:idx]
		queryPart = decoded[idx+1:]
	}

	parts := strings.SplitN(mainPart, ":", 6)
	if len(parts) < 6 {
		return nil, E.New("invalid SSR link format: expected host:port:protocol:method:obfs:password")
	}

	host := parts[0]
	portStr := parts[1]
	protocol := parts[2]
	method := parts[3]
	obfs := parts[4]
	passwordB64 := parts[5]

	port := toInt16(portStr, 443)

	password, err := ssrDecodeBase64(passwordB64)
	if err != nil {
		password = passwordB64
	}

	params := ssrParseQuery(queryPart)

	remarks := ""
	if v, ok := params["remarks"]; ok {
		if d, err := ssrDecodeBase64(v); err == nil {
			remarks = d
		}
	}

	obfsParam := ""
	if v, ok := params["obfsparam"]; ok {
		if d, err := ssrDecodeBase64(v); err == nil {
			obfsParam = d
		}
	}

	protoParam := ""
	if v, ok := params["protoparam"]; ok {
		if d, err := ssrDecodeBase64(v); err == nil {
			protoParam = d
		}
	}

	tag := remarks
	if tag == "" {
		tag = fmt.Sprintf("%s:%d", host, port)
	}

	ssMethod := mapSSRMethod(method)

	result := T.Outbound{
		Type: C.TypeShadowsocksR,
		Tag:  tag,
		ShadowsocksROptions: T.ShadowsocksROutboundOptions{
			ServerOptions: T.ServerOptions{
				Server:     host,
				ServerPort: port,
			},
			Method:        ssMethod,
			Password:      password,
			Obfs:          obfs,
			ObfsParam:     obfsParam,
			Protocol:      protocol,
			ProtocolParam: protoParam,
		},
	}

	return &result, nil
}

func ssrDecodeBase64(s string) (string, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", nil
	}

	s = strings.ReplaceAll(s, "-", "+")
	s = strings.ReplaceAll(s, "_", "/")

	if m := len(s) % 4; m != 0 {
		s += strings.Repeat("=", 4-m)
	}

	data, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

func ssrParseQuery(query string) map[string]string {
	result := make(map[string]string)
	if query == "" {
		return result
	}

	pairs := strings.Split(query, "&")
	for _, pair := range pairs {
		kv := strings.SplitN(pair, "=", 2)
		if len(kv) == 2 {
			result[strings.ToLower(strings.TrimSpace(kv[0]))] = strings.TrimSpace(kv[1])
		}
	}
	return result
}

func mapSSRMethod(method string) string {
	method = strings.ToLower(strings.TrimSpace(method))
	methodMap := map[string]string{
		"none":             "none",
		"table":            "table",
		"rc4":              "rc4",
		"rc4-md5":          "rc4-md5",
		"rc4-md5-6":        "rc4-md5-6",
		"aes-128-cfb":      "aes-128-cfb",
		"aes-192-cfb":      "aes-192-cfb",
		"aes-256-cfb":      "aes-256-cfb",
		"aes-128-ctr":      "aes-128-ctr",
		"aes-192-ctr":      "aes-192-ctr",
		"aes-256-ctr":      "aes-256-ctr",
		"aes-128-ofb":      "aes-128-ofb",
		"aes-192-ofb":      "aes-192-ofb",
		"aes-256-ofb":      "aes-256-ofb",
		"camellia-128-cfb": "camellia-128-cfb",
		"camellia-192-cfb": "camellia-192-cfb",
		"camellia-256-cfb": "camellia-256-cfb",
		"bf-cfb":           "bf-cfb",
		"cast5-cfb":        "cast5-cfb",
		"des-cfb":          "des-cfb",
		"idea-cfb":         "idea-cfb",
		"rc2-cfb":          "rc2-cfb",
		"seed-cfb":         "seed-cfb",
		"salsa20":          "salsa20",
		"chacha20":         "chacha20",
		"chacha20-ietf":    "chacha20-ietf",
	}

	if mapped, ok := methodMap[method]; ok {
		return mapped
	}
	return method
}
