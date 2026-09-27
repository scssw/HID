package outbound

import (
	"context"
	"errors"
	"fmt"
	"net"
	"sync"

	"github.com/sagernet/sing-box/adapter"
	
	"github.com/sagernet/sing-box/common/dialer"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	shadowsocksr "github.com/v2rayA/shadowsocksR"
	"github.com/v2rayA/shadowsocksR/obfs"
	"github.com/v2rayA/shadowsocksR/protocol"
	"github.com/v2rayA/shadowsocksR/ssr"
	cipher "github.com/v2rayA/shadowsocksR/streamCipher"
	"github.com/v2rayA/shadowsocksR/tools/socks"
	E "github.com/sagernet/sing/common/exceptions"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)



var _ adapter.Outbound = (*Outbound)(nil)

type Outbound struct {
	myOutboundAdapter
	logger       log.ContextLogger
	dialer       N.Dialer
	serverAddr   M.Socksaddr
	options      option.ShadowsocksROutboundOptions
	protocolMu   sync.Mutex
	protocolData any
	obfsData     any
}

func NewShadowsocksR(ctx context.Context, router adapter.Router, logger log.ContextLogger, tag string, options option.ShadowsocksROutboundOptions) (adapter.Outbound, error) {
	if options.Password == "" {
		return nil, E.New("missing password")
	}
	if options.Method == "" {
		options.Method = "none"
	}
	if options.Obfs == "" {
		options.Obfs = "plain"
	}
	if options.Protocol == "" {
		options.Protocol = "origin"
	}
	outboundDialer, err := dialer.New(router, options.DialerOptions)
	if err != nil {
		return nil, err
	}
	networks := []string{N.NetworkTCP}
	return &Outbound{
		myOutboundAdapter: myOutboundAdapter{protocol: C.TypeShadowsocksR, network: networks, router: router, logger: logger, tag: tag, dependencies: withDialerDependency(options.DialerOptions)},
		logger:     logger,
		dialer:     outboundDialer,
		serverAddr: options.ServerOptions.Build(),
		options:    options,
	}, nil
}

func (h *Outbound) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	if network != N.NetworkTCP {
		return nil, E.Extend(N.ErrUnknownNetwork, network)
	}
	ctx, metadata := adapter.ExtendContext(ctx)
	metadata.Outbound = h.Tag()
	metadata.Destination = destination
	h.logger.InfoContext(ctx, "outbound connection to ", destination)

	conn, err := h.dialer.DialContext(ctx, N.NetworkTCP, h.serverAddr)
	if err != nil {
		return nil, err
	}

	target := socks.ParseAddr(destination.String())
	if target == nil {
		conn.Close()
		return nil, fmt.Errorf("[ssr] unable to parse address: %s", destination.String())
	}

	streamCipher, err := cipher.NewStreamCipher(h.options.Method, h.options.Password)
	if err != nil {
		conn.Close()
		return nil, err
	}

	ssrconn := shadowsocksr.NewSSTCPConn(conn, streamCipher)
	if ssrconn.Conn == nil {
		conn.Close()
		return nil, errors.New("[ssr] nil connection")
	}

	serverHost := h.serverAddr.AddrString()
	serverPort := h.serverAddr.Port

	ssrconn.IObfs = obfs.NewObfs(h.options.Obfs)
	if ssrconn.IObfs == nil {
		ssrconn.Close()
		return nil, fmt.Errorf("[ssr] unsupported obfs type: %s", h.options.Obfs)
	}

	obfsServerInfo := &ssr.ServerInfo{
		Host:   serverHost,
		Port:   serverPort,
		TcpMss: 1460,
		Param:  h.options.ObfsParam,
	}
	ssrconn.IObfs.SetServerInfo(obfsServerInfo)

	ssrconn.IProtocol = protocol.NewProtocol(h.options.Protocol)
	if ssrconn.IProtocol == nil {
		ssrconn.Close()
		return nil, fmt.Errorf("[ssr] unsupported protocol type: %s", h.options.Protocol)
	}

	protocolServerInfo := &ssr.ServerInfo{
		Host:   serverHost,
		Port:   serverPort,
		TcpMss: 1460,
		Param:  h.options.ProtocolParam,
	}
	ssrconn.IProtocol.SetServerInfo(protocolServerInfo)

	h.protocolMu.Lock()
	if h.obfsData == nil {
		h.obfsData = ssrconn.IObfs.GetData()
	}
	ssrconn.IObfs.SetData(h.obfsData)

	if h.protocolData == nil {
		h.protocolData = ssrconn.IProtocol.GetData()
	}
	ssrconn.IProtocol.SetData(h.protocolData)

	_, err = ssrconn.Write(target)
	h.protocolMu.Unlock()

	if err != nil {
		ssrconn.Close()
		return nil, err
	}

	return ssrconn, nil
}

func (h *Outbound) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	return nil, E.New("UDP is not supported by ShadowsocksR")
}




func (h *Outbound) NewConnection(ctx context.Context, conn net.Conn, metadata adapter.InboundContext) error {
	return NewConnection(ctx, h, conn, metadata)
}

func (h *Outbound) NewPacketConnection(ctx context.Context, conn N.PacketConn, metadata adapter.InboundContext) error {
	return NewPacketConnection(ctx, h, conn, metadata)
}



