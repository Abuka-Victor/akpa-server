package internal

import (
	"fmt"
	"net"
	"os"
)

func RunTCPServer() {
	listener, err := net.Listen("tcp", ":7000")
	if err != nil {
		fmt.Println("Error starting TCP socket server:", err)
		return
	}
	defer listener.Close()

	for {
		conn, err := listener.Accept()
		if err != nil {
			fmt.Println("Error accepting connection:", err)
			continue
		}
		fmt.Println("Somebody connected!")

		connId := AppRegistry.AddTunnel(conn)
		fmt.Println("The connection ID is:", connId)

		if os.Getenv("APP_ENV") == "production" {
			conn.Write([]byte("Your link is live at https://akpa.victorabuka.com/live/" + connId + "\n"))
		} else {
			conn.Write([]byte(connId + "\n"))
			fmt.Println("Sent url link for", connId)
		}

	}
}
