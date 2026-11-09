#!/usr/bin/env python3

"""Tkinter UI for the UDP coordination client."""

import queue
import asyncio
import json
import threading
import tkinter as tk
from tkinter import messagebox, ttk

from client import ClientConnection, DEST_ADDR, DEST_PORT, SOURCE_PORT

DEFAULT_COORDINATOR = DEST_ADDR
DEFAULT_COORDINATOR_PORT = str(DEST_PORT)
DEFAULT_LOCAL_PORT = str(SOURCE_PORT)


class UIClientConnection(ClientConnection):
    """Client connection with a UI callback for coordinator peer updates."""

    def __init__(self, *args, on_peer_update=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.on_peer_update = on_peer_update or (lambda clients: None)

    def listen_to_coordination_server(self):
        if self.mode != 0:
            print("Trying to listen to coordination server when not connected to one.")
            return

        while True:
            try:
                message = self.socket.recv(1024)
                if not message:
                    return

                message = json.loads(message)
                if message.get("messageType") == 2:
                    self.on_peer_update(message.get("clients", []))
                    continue
                if message.get("messageType") == 1:
                    return message
            except Exception as error:
                print(error)


class ClientUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Peer Link")
        self.root.geometry("720x540")
        self.root.minsize(620, 460)

        self.events = queue.Queue()
        self.connection = None
        self.worker = None
        self.loop = None
        self.stop_event = threading.Event()
        self.state = "Disconnected"

        self.coordinator_var = tk.StringVar(value=DEFAULT_COORDINATOR)
        self.coordinator_port_var = tk.StringVar(value=DEFAULT_COORDINATOR_PORT)
        self.local_port_var = tk.StringVar(value=DEFAULT_LOCAL_PORT)
        self.peer_ip_var = tk.StringVar()
        self.peer_port_var = tk.StringVar()
        self.message_var = tk.StringVar()
        self.status_var = tk.StringVar(value=self.state)

        self._build_ui()
        self.root.after(100, self._process_events)
        self.root.protocol("WM_DELETE_WINDOW", self.close)

    def _build_ui(self):
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(1, weight=1)

        header = ttk.Frame(self.root, padding=(18, 16, 18, 10))
        header.grid(row=0, column=0, sticky="ew")
        header.columnconfigure(1, weight=1)
        ttk.Label(header, text="Peer Link", font=("Helvetica", 20, "bold")).grid(
            row=0, column=0, sticky="w"
        )
        ttk.Label(header, textvariable=self.status_var).grid(
            row=0, column=2, padx=(12, 0), sticky="e"
        )

        content = ttk.Frame(self.root, padding=(18, 0, 18, 18))
        content.grid(row=1, column=0, sticky="nsew")
        content.columnconfigure(0, weight=1)
        content.rowconfigure(2, weight=1)

        connection = ttk.LabelFrame(content, text="Connection", padding=12)
        connection.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        for column in range(6):
            connection.columnconfigure(column, weight=1 if column in (1, 3, 5) else 0)

        ttk.Label(connection, text="Coordinator").grid(row=0, column=0, sticky="w")
        ttk.Entry(connection, textvariable=self.coordinator_var).grid(
            row=0, column=1, padx=(8, 16), sticky="ew"
        )
        ttk.Label(connection, text="Port").grid(row=0, column=2, sticky="w")
        ttk.Entry(connection, textvariable=self.coordinator_port_var, width=8).grid(
            row=0, column=3, padx=(8, 16), sticky="ew"
        )
        ttk.Label(connection, text="Local UDP port").grid(row=0, column=4, sticky="w")
        ttk.Entry(connection, textvariable=self.local_port_var, width=8).grid(
            row=0, column=5, padx=(8, 0), sticky="ew"
        )

        actions = ttk.Frame(content)
        actions.grid(row=1, column=0, sticky="ew", pady=(0, 10))
        actions.columnconfigure(1, weight=1)
        ttk.Label(actions, text="Peer IP").grid(row=0, column=0, sticky="w")
        ttk.Entry(actions, textvariable=self.peer_ip_var).grid(
            row=0, column=1, padx=(8, 8), sticky="ew"
        )
        ttk.Label(actions, text="Port").grid(row=0, column=2, sticky="w")
        ttk.Entry(actions, textvariable=self.peer_port_var, width=8).grid(
            row=0, column=3, padx=(8, 8)
        )
        self.connect_button = ttk.Button(actions, text="Connect", command=self.connect)
        self.connect_button.grid(row=0, column=4, padx=(0, 8))
        self.request_button = ttk.Button(
            actions, text="Request peer", command=self.request_peer, state="disabled"
        )
        self.request_button.grid(row=0, column=5)

        log_frame = ttk.LabelFrame(content, text="Activity", padding=8)
        log_frame.grid(row=2, column=0, sticky="nsew")
        log_frame.columnconfigure(0, weight=1)
        log_frame.rowconfigure(0, weight=1)
        self.log = tk.Text(log_frame, state="disabled", wrap="word", height=15)
        self.log.grid(row=0, column=0, sticky="nsew")
        scrollbar = ttk.Scrollbar(log_frame, command=self.log.yview)
        scrollbar.grid(row=0, column=1, sticky="ns")
        self.log.configure(yscrollcommand=scrollbar.set)

        composer = ttk.Frame(content, padding=(0, 10, 0, 0))
        composer.grid(row=3, column=0, sticky="ew")
        composer.columnconfigure(0, weight=1)
        self.message_entry = ttk.Entry(composer, textvariable=self.message_var, state="disabled")
        self.message_entry.grid(row=0, column=0, sticky="ew", padx=(0, 8))
        self.message_entry.bind("<Return>", lambda _event: self.send_message())
        self.send_button = ttk.Button(
            composer, text="Send", command=self.send_message, state="disabled"
        )
        self.send_button.grid(row=0, column=1)

    def connect(self):
        if self.connection is not None:
            self.disconnect()
            return

        try:
            coordinator = self.coordinator_var.get().strip()
            coordinator_port = int(self.coordinator_port_var.get())
            local_port = int(self.local_port_var.get())
            if not coordinator:
                raise ValueError("Coordinator address is empty")
        except ValueError as error:
            messagebox.showerror("Invalid connection settings", str(error))
            return

        self.connect_button.configure(text="Disconnect")
        self.request_button.configure(state="normal")
        self._set_status("Connecting")
        self.connection = UIClientConnection(
            source_addr="",
            source_port=local_port,
            dest_addr=coordinator,
            dest_port=coordinator_port,
            on_peer_update=self._peer_update,
        )
        self.stop_event.clear()
        self.worker = threading.Thread(target=self._run_session, daemon=True)
        self.worker.start()
        self._write(f"Connecting to {coordinator}:{coordinator_port}")

    def disconnect(self):
        if self.connection is not None:
            self.stop_event.set()
            interval = getattr(self.connection, "interval", None)
            if interval is not None:
                interval["cancel"]()
            network_socket = getattr(self.connection, "socket", None)
            if network_socket is not None:
                network_socket.close()
            self.connection = None
        self.connect_button.configure(text="Connect")
        self.request_button.configure(state="disabled")
        self.send_button.configure(state="disabled")
        self.message_entry.configure(state="disabled")
        self._set_status("Disconnected")
        self._write("Disconnected")

    def request_peer(self):
        try:
            peer_ip = self.peer_ip_var.get().strip()
            peer_port = int(self.peer_port_var.get())
            if not peer_ip:
                raise ValueError("Peer IP is empty")
        except ValueError as error:
            messagebox.showerror("Invalid peer", str(error))
            return

        try:
            self.connection.socket.sendall(json.dumps({
                "messageType": 2,
                "peer": {"ip": peer_ip, "port": peer_port},
            }).encode())
            self._write(f"Requested peer {peer_ip}:{peer_port}")
        except (AttributeError, OSError) as error:
            self._write(f"Could not request peer: {error}")

    def send_message(self):
        message = self.message_var.get().strip()
        if not message or not self.connection:
            return
        try:
            self.connection.socket.sendall(json.dumps({
                "messageType": 1,
                "message": message,
            }).encode())
            self._write(f"You: {message}")
            self.message_var.set("")
        except OSError as error:
            self._write(f"Send failed: {error}")

    def _run_session(self):
        asyncio.run(self._session())

    async def _session(self):
        try:
            self.loop = asyncio.get_running_loop()
            self._set_status("Waiting for peer")
            await self.connection.connect_to_server()
            self._write("Connected to coordination server")

            peer = await asyncio.to_thread(
                self.connection.listen_to_coordination_server
            )
            if self.stop_event.is_set() or not peer:
                return

            self._write(f"Peer selected: {peer.get('peer')}")
            await self.connection.disconnect()
            await self.connection.connect_to_peer(peer)
            self._set_status("Connected to peer")
            self._write("Peer connection established")
            self.events.put(("peer_ready", None))

            if peer.get("role") == 0:
                await asyncio.to_thread(self._listen_for_peer_messages)
            else:
                while not self.stop_event.is_set():
                    await asyncio.sleep(0.1)
        except Exception as error:
            if not self.stop_event.is_set():
                self.events.put(("error", str(error)))
                self._set_status("Error")
        finally:
            self.loop = None

    def _listen_for_peer_messages(self):
        while not self.stop_event.is_set():
            try:
                message = self.connection.socket.recv(1024)
                if not message:
                    return
                decoded = json.loads(message)
                if decoded.get("messageType") != 0:
                    self._write(f"Peer: {decoded.get('message', decoded)}")
            except (OSError, json.JSONDecodeError) as error:
                if not self.stop_event.is_set():
                    self._write(f"Peer receive error: {error}")
                return

    def _peer_update(self, clients):
        if not clients:
            self._write("Coordinator peer update: no peers available")
            return

        endpoints = []
        for client in clients:
            address = client.get("address")
            port = client.get("port")
            endpoints.append(f"{address}:{port}")
        self._write("Coordinator peer update: " + ", ".join(endpoints))

    def _set_status(self, status):
        self.events.put(("status", status))

    def _write(self, message):
        self.events.put(("log", message))

    def _process_events(self):
        try:
            while True:
                event, payload = self.events.get_nowait()
                if event == "log":
                    self.log.configure(state="normal")
                    self.log.insert("end", payload + "\n")
                    self.log.see("end")
                    self.log.configure(state="disabled")
                elif event == "status":
                    self.status_var.set(payload)
                elif event == "peer_ready":
                    self.send_button.configure(state="normal")
                    self.message_entry.configure(state="normal")
                    self.message_entry.focus_set()
                elif event == "error":
                    self._write(f"Error: {payload}")
                    self._set_status("Error")
        except queue.Empty:
            pass
        self.root.after(100, self._process_events)

    def close(self):
        self.disconnect()
        self.root.destroy()


if __name__ == "__main__":
    app_root = tk.Tk()
    ClientUI(app_root)
    app_root.mainloop()
