package internal

import (
	"math/rand"
	"net"
	"sync"
	"time"
)

type Registry struct {
	ru     sync.RWMutex
	tunnel map[string]net.Conn
	timers map[string]*time.Timer
}

var AppRegistry = NewRegistry()

const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

func generateID() string {
	b := make([]byte, 16)
	for i := 0; i < 16; i++ {
		b[i] = letters[rand.Intn(len(letters))]
	}
	return string(b)
}

func NewRegistry() *Registry {
	return &Registry{
		tunnel: make(map[string]net.Conn),
		timers: make(map[string]*time.Timer),
	}
}

func (r *Registry) FindTunnelByID(id string) net.Conn {
	r.ru.RLock()
	defer r.ru.RUnlock()
	return r.tunnel[id]
}

func (r *Registry) AddTunnel(tunnel net.Conn) string {
	r.ru.Lock()
	defer r.ru.Unlock()
	id := generateID()
	r.tunnel[id] = tunnel

	r.timers[id] = time.AfterFunc(1*time.Hour, func() {
		r.RemoveTunnel(id)
	})

	return id
}

func (r *Registry) RemoveTunnel(id string) {
	r.ru.Lock()
	defer r.ru.Unlock()

	if timer, exists := r.timers[id]; exists {
		timer.Stop()
		delete(r.timers, id)
	}

	if conn, exists := r.tunnel[id]; exists {
		conn.Close()
		delete(r.tunnel, id)
	}
}

func (r *Registry) TunnelCount() int {
	r.ru.RLock()
	defer r.ru.RUnlock()
	return len(r.tunnel)
}
