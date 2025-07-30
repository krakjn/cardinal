package main

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// DDS Message structure
type DDSMessage struct {
	Content   string
	Timestamp time.Time
}

// Interface for DDS publishers
type DDSPublisher interface {
	Publish(msg DDSMessage) error
}

// Interface for DDS subscribers
type DDSSubscriber interface {
	Subscribe() <-chan DDSMessage
}

// Simple DDS-like message channel (simulating Fast DDS for fallback)
type MockDDSPublisher struct {
	topic   string
	channel chan DDSMessage
}

type MockDDSSubscriber struct {
	topic   string
	channel chan DDSMessage
}

// Create a simple DDS-like system
func NewDDSSystem() (*MockDDSPublisher, *MockDDSSubscriber) {
	channel := make(chan DDSMessage, 100)
	pub := &MockDDSPublisher{topic: "hello_topic", channel: channel}
	sub := &MockDDSSubscriber{topic: "hello_topic", channel: channel}
	return pub, sub
}

func (p *MockDDSPublisher) Publish(msg DDSMessage) error {
	p.channel <- msg
	return nil
}

func (s *MockDDSSubscriber) Subscribe() <-chan DDSMessage {
	return s.channel
}

// TUI Model using Bubble Tea
type model struct {
	messages []DDSMessage
	style    lipgloss.Style
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		}
	case DDSMessage:
		m.messages = append(m.messages, msg)
		// Keep only last 10 messages
		if len(m.messages) > 10 {
			m.messages = m.messages[1:]
		}
	}
	return m, nil
}

func (m model) View() string {
	// Define styles
	titleStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("#FAFAFA")).
		Background(lipgloss.Color("#7D56F4")).
		Padding(0, 1).
		MarginBottom(1)

	messageStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("#04B575")).
		Padding(0, 2).
		MarginLeft(2)

	timestampStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("#626262")).
		Italic(true)

	borderStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("#874BFD")).
		Padding(1, 2).
		Width(80)

	var content string
	content += titleStyle.Render("Cardinal - Fast DDS + Lipgloss Demo")
	content += "\n\n"

	if len(m.messages) == 0 {
		content += messageStyle.Render("Waiting for messages...")
	} else {
		content += messageStyle.Render("Recent DDS Messages:")
		content += "\n"
		for _, msg := range m.messages {
			content += "\n"
			content += messageStyle.Render("• " + msg.Content)
			content += " "
			content += timestampStyle.Render(msg.Timestamp.Format("15:04:05"))
		}
	}

	content += "\n\n"
	content += lipgloss.NewStyle().Foreground(lipgloss.Color("#626262")).Render("Press 'q' or Ctrl+C to quit")

	return borderStyle.Render(content)
}

// Hello World Publisher Thread
func helloWorldPublisher(ctx context.Context, pub DDSPublisher, wg *sync.WaitGroup) {
	defer wg.Done()

	counter := 0
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			log.Println("Hello World Publisher: Shutting down...")
			return
		case <-ticker.C:
			counter++
			msg := DDSMessage{
				Content:   fmt.Sprintf("Hello World #%d", counter),
				Timestamp: time.Now(),
			}
			if err := pub.Publish(msg); err != nil {
				log.Printf("Error publishing: %v", err)
			} else {
				log.Printf("Published: %s\n", msg.Content)
			}
		}
	}
}

// TUI Subscriber Thread
func tuiSubscriber(ctx context.Context, sub DDSSubscriber, program *tea.Program, wg *sync.WaitGroup) {
	defer wg.Done()

	msgChan := sub.Subscribe()

	for {
		select {
		case <-ctx.Done():
			log.Println("TUI Subscriber: Shutting down...")
			return
		case msg := <-msgChan:
			// Send the DDS message to the TUI
			program.Send(msg)
		}
	}
}

func main() {
	// Try real DDS first, fallback to mock
	realPub, realSub, err := NewRealDDSSystem(0, "hello_topic")
	if err != nil {
		// Fallback to mock DDS
		fmt.Println("⚠️ Real DDS failed, using mock DDS:", err)
		mockPub, mockSub := NewDDSSystem()
		runApplication(mockPub, mockSub)
	} else {
		fmt.Println("✅ Using real Fast DDS!")

		// Cleanup real DDS on exit
		defer realPub.Cleanup()
		defer realSub.Cleanup()

		runApplication(realPub, realSub)
	}
}

func runApplication(pub DDSPublisher, sub DDSSubscriber) {
	// Create TUI model
	m := model{
		messages: []DDSMessage{},
		style:    lipgloss.NewStyle(),
	}

	// Create Bubble Tea program
	program := tea.NewProgram(m, tea.WithAltScreen())

	// Create context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	var wg sync.WaitGroup

	// Start the hello world publisher thread
	wg.Add(1)
	go helloWorldPublisher(ctx, pub, &wg)

	// Start the TUI subscriber thread
	wg.Add(1)
	go tuiSubscriber(ctx, sub, program, &wg)

	// Handle program termination
	go func() {
		if _, err := program.Run(); err != nil {
			log.Printf("Error running program: %v", err)
		}
		cancel() // Signal all goroutines to stop
	}()

	// Wait for all goroutines to finish
	wg.Wait()

	fmt.Println("Cardinal application terminated.")
}
