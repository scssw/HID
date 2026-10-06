package option

type AnyTLSOutboundOptions struct {
	DialerOptions
	ServerOptions
	Password                 string      `json:"password"`
	IdleSessionCheckInterval Duration    `json:"idle_session_check_interval,omitempty"`
	IdleSessionTimeout       Duration    `json:"idle_session_timeout,omitempty"`
	MinIdleSession           int         `json:"min_idle_session,omitempty"`
	ClientMetadata           string      `json:"client_metadata,omitempty"`
	Network                  NetworkList `json:"network,omitempty"`
	OutboundTLSOptionsContainer
}
