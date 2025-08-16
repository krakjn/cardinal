package main

import (
	"context"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// DDS Message structure
type DDSMessage struct {
	Content   string
	Timestamp time.Time
}

// System metrics for the TUI
type SystemMetrics struct {
	MessagesReceived   int
	MessagesPublished  int
	MessageRate        float64
	ConnectionStatus   string
	Uptime             time.Duration
	LastMessageLatency time.Duration
	ErrorCount         int
}

// Tick message for periodic updates
type tickMsg struct{}

// Metrics update message
type metricsMsg SystemMetrics

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

// Tab represents a tab in the TUI
type Tab struct {
	name string
	key  string
}

// Available tabs
var tabs = []Tab{
	{name: "📊 Dashboard", key: "dashboard"},
	{name: "💬 Messages", key: "messages"},
	{name: "📈 Charts", key: "charts"},
	{name: "⚙️ Settings", key: "settings"},
}

// TUI Model using Bubble Tea
type model struct {
	messages        []DDSMessage
	metrics         SystemMetrics
	startTime       time.Time
	spinner         spinner.Model
	progressBar     progress.Model
	connectionBar   progress.Model
	messageRateHist []float64
	width           int
	height          int
	usingRealDDS    bool
	activeTab       int
}

func (m model) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		tea.Tick(time.Second, func(time.Time) tea.Msg {
			return tickMsg{}
		}),
	)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.progressBar.Width = msg.Width - 20
		m.connectionBar.Width = msg.Width - 20

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "1", "2", "3", "4":
			// Switch tabs with number keys
			if tabIndex := int(msg.String()[0]) - '1'; tabIndex >= 0 && tabIndex < len(tabs) {
				m.activeTab = tabIndex
			}
		case "tab":
			// Cycle through tabs with Tab key
			m.activeTab = (m.activeTab + 1) % len(tabs)
		case "shift+tab":
			// Cycle backwards through tabs with Shift+Tab
			m.activeTab = (m.activeTab - 1 + len(tabs)) % len(tabs)
		case "left", "h":
			// Navigate left through tabs
			m.activeTab = (m.activeTab - 1 + len(tabs)) % len(tabs)
		case "right", "l":
			// Navigate right through tabs
			m.activeTab = (m.activeTab + 1) % len(tabs)
		}

	case tickMsg:
		// Update metrics
		m.metrics.Uptime = time.Since(m.startTime)

		// Update message rate history (last 10 seconds)
		m.messageRateHist = append(m.messageRateHist, m.metrics.MessageRate)
		if len(m.messageRateHist) > 10 {
			m.messageRateHist = m.messageRateHist[1:]
		}

		cmds = append(cmds, tea.Tick(time.Second, func(time.Time) tea.Msg {
			return tickMsg{}
		}))

	case DDSMessage:
		m.messages = append(m.messages, msg)
		m.metrics.MessagesReceived++
		m.metrics.LastMessageLatency = time.Since(msg.Timestamp)

		// Calculate message rate (messages per second over last 10 seconds)
		if len(m.messageRateHist) > 0 {
			m.metrics.MessageRate = float64(m.metrics.MessagesReceived) / float64(len(m.messageRateHist))
		}

		// Keep only last 15 messages
		if len(m.messages) > 15 {
			m.messages = m.messages[1:]
		}

	case metricsMsg:
		m.metrics = SystemMetrics(msg)

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		cmds = append(cmds, cmd)
	}

	return m, tea.Batch(cmds...)
}

func (m model) View() string {
	if m.width == 0 {
		return "Loading..."
	}

	// Define color palette
	var (
		primaryColor = lipgloss.Color("#00D7FF") // Cyan
		successColor = lipgloss.Color("#51CF66") // Green
		warningColor = lipgloss.Color("#FFD93D") // Yellow
		textColor    = lipgloss.Color("#F8F8F2") // Light
		dimColor     = lipgloss.Color("#6E7681") // Dim
		accentColor  = lipgloss.Color("#FF6B6B") // Coral
	)

	// Render the tab bar
	tabBar := m.renderTabBar(primaryColor, textColor, dimColor, accentColor)

	// Render the active tab content
	var content string
	switch tabs[m.activeTab].key {
	case "dashboard":
		content = m.renderDashboard(primaryColor, successColor, warningColor, textColor, dimColor)
	case "messages":
		content = m.renderMessages(primaryColor, textColor, dimColor)
	case "charts":
		content = m.renderCharts(primaryColor, textColor, dimColor, accentColor)
	case "settings":
		content = m.renderSettings(primaryColor, textColor, dimColor)
	default:
		content = m.renderDashboard(primaryColor, successColor, warningColor, textColor, dimColor)
	}

	// Footer with navigation hints
	footer := m.renderFooter(dimColor)

	return lipgloss.JoinVertical(lipgloss.Left, tabBar, content, footer)
}

// Render the tab bar
func (m model) renderTabBar(primaryColor, textColor, dimColor, accentColor lipgloss.Color) string {
	var renderedTabs []string

	for i, tab := range tabs {
		var style lipgloss.Style
		if i == m.activeTab {
			// Active tab style
			style = lipgloss.NewStyle().
				Foreground(textColor).
				Background(primaryColor).
				Bold(true).
				Padding(0, 2).
				Border(lipgloss.RoundedBorder()).
				BorderForeground(primaryColor)
		} else {
			// Inactive tab style
			style = lipgloss.NewStyle().
				Foreground(dimColor).
				Background(lipgloss.Color("#1A1A2E")).
				Padding(0, 2).
				Border(lipgloss.RoundedBorder()).
				BorderForeground(dimColor)
		}

		tabText := fmt.Sprintf("[%d] %s", i+1, tab.name)
		renderedTabs = append(renderedTabs, style.Render(tabText))
	}

	tabBarStyle := lipgloss.NewStyle().
		Width(m.width - 4).
		Align(lipgloss.Left).
		MarginBottom(1)

	return tabBarStyle.Render(lipgloss.JoinHorizontal(lipgloss.Left, renderedTabs...))
}

// Render the dashboard tab
func (m model) renderDashboard(primaryColor, successColor, warningColor, textColor, dimColor lipgloss.Color) string {
	cardStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(primaryColor).
		Padding(1, 2).
		MarginBottom(1)

	headerStyle := lipgloss.NewStyle().
		Foreground(primaryColor).
		Bold(true).
		MarginBottom(1)

	metricLabelStyle := lipgloss.NewStyle().
		Foreground(dimColor).
		Width(20)

	metricValueStyle := lipgloss.NewStyle().
		Foreground(textColor).
		Bold(true)

	statusStyle := func(status string) lipgloss.Style {
		if strings.Contains(status, "Connected") || status == "✅ Real DDS" {
			return lipgloss.NewStyle().Foreground(successColor).Bold(true)
		}
		return lipgloss.NewStyle().Foreground(warningColor).Bold(true)
	}

	var sections []string

	// Status and metrics section
	connectionStatus := "⚠️  Mock DDS"
	if m.usingRealDDS {
		connectionStatus = "✅ Real DDS"
	}

	// Calculate connection progress
	connectionProgress := 0.8
	if m.usingRealDDS && m.metrics.ErrorCount == 0 {
		connectionProgress = 1.0
	} else if m.metrics.ErrorCount > 5 {
		connectionProgress = 0.3
	}

	// Message rate progress
	maxExpectedRate := 10.0
	rateProgress := m.metrics.MessageRate / maxExpectedRate
	if rateProgress > 1.0 {
		rateProgress = 1.0
	}

	metricsContent := lipgloss.JoinVertical(lipgloss.Left,
		headerStyle.Render("📊 System Overview"),
		lipgloss.JoinHorizontal(lipgloss.Left,
			metricLabelStyle.Render("Status:"),
			statusStyle(connectionStatus).Render(connectionStatus),
		),
		lipgloss.JoinHorizontal(lipgloss.Left,
			metricLabelStyle.Render("Uptime:"),
			metricValueStyle.Render(formatDuration(m.metrics.Uptime)),
		),
		lipgloss.JoinHorizontal(lipgloss.Left,
			metricLabelStyle.Render("Messages Received:"),
			metricValueStyle.Render(fmt.Sprintf("%d", m.metrics.MessagesReceived)),
		),
		lipgloss.JoinHorizontal(lipgloss.Left,
			metricLabelStyle.Render("Message Rate:"),
			metricValueStyle.Render(fmt.Sprintf("%.1f/sec", m.metrics.MessageRate)),
		),
		"",
		lipgloss.JoinHorizontal(lipgloss.Left,
			metricLabelStyle.Render("Connection Health:"),
			m.connectionBar.ViewAs(connectionProgress),
		),
		lipgloss.JoinHorizontal(lipgloss.Left,
			metricLabelStyle.Render("Message Throughput:"),
			m.progressBar.ViewAs(rateProgress),
		),
	)
	sections = append(sections, cardStyle.Render(metricsContent))

	// Quick charts section
	if len(m.messageRateHist) > 0 {
		chartContent := lipgloss.JoinVertical(lipgloss.Left,
			headerStyle.Render("📈 Quick View - Message Rate"),
			renderSparkline(m.messageRateHist),
		)
		sections = append(sections, cardStyle.Render(chartContent))
	}

	return lipgloss.JoinVertical(lipgloss.Left, sections...)
}

// Render the messages tab
func (m model) renderMessages(primaryColor, textColor, dimColor lipgloss.Color) string {
	cardStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(primaryColor).
		Padding(1, 2).
		MarginBottom(1)

	headerStyle := lipgloss.NewStyle().
		Foreground(primaryColor).
		Bold(true).
		MarginBottom(1)

	messageStyle := lipgloss.NewStyle().
		Foreground(textColor).
		Padding(0, 1)

	timestampStyle := lipgloss.NewStyle().
		Foreground(dimColor).
		Italic(true)

	var sections []string

	// Messages section
	messageContent := headerStyle.Render("💬 DDS Message Stream") + "\n"
	if len(m.messages) == 0 {
		messageContent += lipgloss.NewStyle().
			Foreground(dimColor).
			Italic(true).
			Render("Waiting for messages... " + m.spinner.View())
	} else {
		for i, msg := range m.messages {
			var indicator string
			age := time.Since(msg.Timestamp)
			if age < 5*time.Second {
				indicator = "🟢"
			} else if age < 30*time.Second {
				indicator = "🟡"
			} else {
				indicator = "⚪"
			}

			messageContent += fmt.Sprintf("%s %s %s\n",
				indicator,
				messageStyle.Render(msg.Content),
				timestampStyle.Render(msg.Timestamp.Format("15:04:05")),
			)

			// Add separator for readability
			if i < len(m.messages)-1 {
				messageContent += lipgloss.NewStyle().
					Foreground(dimColor).
					Render("  ├─────────────────────────") + "\n"
			}
		}
	}

	// Message statistics
	statsContent := lipgloss.JoinVertical(lipgloss.Left,
		headerStyle.Render("📈 Message Statistics"),
		fmt.Sprintf("Total Messages: %d", m.metrics.MessagesReceived),
		fmt.Sprintf("Current Rate: %.1f msg/sec", m.metrics.MessageRate),
		fmt.Sprintf("Average Latency: %v", m.metrics.LastMessageLatency),
	)

	sections = append(sections, cardStyle.Render(messageContent))
	sections = append(sections, cardStyle.Render(statsContent))

	return lipgloss.JoinVertical(lipgloss.Left, sections...)
}

// Render the charts tab
func (m model) renderCharts(primaryColor, textColor, dimColor, accentColor lipgloss.Color) string {
	cardStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(primaryColor).
		Padding(1, 2).
		MarginBottom(1)

	headerStyle := lipgloss.NewStyle().
		Foreground(primaryColor).
		Bold(true).
		MarginBottom(1)

	var sections []string

	// Message rate chart
	if len(m.messageRateHist) > 0 {
		chartContent := lipgloss.JoinVertical(lipgloss.Left,
			headerStyle.Render("📈 Message Rate Over Time"),
			renderSparkline(m.messageRateHist),
			"",
			lipgloss.NewStyle().Foreground(dimColor).Render("Legend: ▁▂▃▄▅▆▇█ (Low to High)"),
		)
		sections = append(sections, cardStyle.Render(chartContent))
	}

	// Connection health over time (simulated)
	healthData := make([]float64, 10)
	for i := range healthData {
		if m.usingRealDDS {
			healthData[i] = 0.8 + 0.2*float64(i%3)/2 // Simulate some variation
		} else {
			healthData[i] = 0.6 + 0.2*float64(i%2) // Mock data pattern
		}
	}

	healthChart := lipgloss.JoinVertical(lipgloss.Left,
		headerStyle.Render("🔗 Connection Health Trend"),
		renderSparkline(healthData),
		"",
		lipgloss.NewStyle().Foreground(dimColor).Render("Recent connection stability metrics"),
	)
	sections = append(sections, cardStyle.Render(healthChart))

	// System performance metrics
	perfContent := lipgloss.JoinVertical(lipgloss.Left,
		headerStyle.Render("⚡ Performance Metrics"),
		fmt.Sprintf("Peak Message Rate: %.1f msg/sec", getMaxRate(m.messageRateHist)),
		fmt.Sprintf("Average Rate: %.1f msg/sec", getAvgRate(m.messageRateHist)),
		fmt.Sprintf("Uptime: %s", formatDuration(m.metrics.Uptime)),
		fmt.Sprintf("Error Count: %d", m.metrics.ErrorCount),
	)
	sections = append(sections, cardStyle.Render(perfContent))

	return lipgloss.JoinVertical(lipgloss.Left, sections...)
}

// Render the settings tab
func (m model) renderSettings(primaryColor, textColor, dimColor lipgloss.Color) string {
	cardStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(primaryColor).
		Padding(1, 2).
		MarginBottom(1)

	headerStyle := lipgloss.NewStyle().
		Foreground(primaryColor).
		Bold(true).
		MarginBottom(1)

	var sections []string

	// Configuration section
	configContent := lipgloss.JoinVertical(lipgloss.Left,
		headerStyle.Render("⚙️ System Configuration"),
		fmt.Sprintf("DDS Mode: %s", func() string {
			if m.usingRealDDS {
				return "FastDDS (Real)"
			}
			return "Mock DDS (Development)"
		}()),
		fmt.Sprintf("Update Interval: 1 second"),
		fmt.Sprintf("Max Message History: 15 messages"),
		fmt.Sprintf("Chart History: %d data points", len(m.messageRateHist)),
	)
	sections = append(sections, cardStyle.Render(configContent))

	// Controls section
	controlsContent := lipgloss.JoinVertical(lipgloss.Left,
		headerStyle.Render("🎮 Controls"),
		"Tab Navigation:",
		"  • [1-4] or Tab/Shift+Tab: Switch tabs",
		"  • ←/→ or h/l: Navigate tabs",
		"  • q or Ctrl+C: Quit",
		"",
		"Tabs Available:",
		"  • [1] Dashboard: System overview",
		"  • [2] Messages: DDS message stream",
		"  • [3] Charts: Performance visualizations",
		"  • [4] Settings: Configuration & help",
	)
	sections = append(sections, cardStyle.Render(controlsContent))

	// About section
	aboutContent := lipgloss.JoinVertical(lipgloss.Left,
		headerStyle.Render("ℹ️ About Cardinal"),
		"Cardinal v1.0 - FastDDS TUI Monitor",
		"Built with Go + Bubble Tea + Lipgloss",
		"C++ FastDDS library built with Zig",
		"",
		"Features:",
		"  • Real-time DDS message monitoring",
		"  • Beautiful terminal interface",
		"  • ASCII charts and progress bars",
		"  • Native builds (no Docker required)",
	)
	sections = append(sections, cardStyle.Render(aboutContent))

	return lipgloss.JoinVertical(lipgloss.Left, sections...)
}

// Render the footer
func (m model) renderFooter(dimColor lipgloss.Color) string {
	footer := lipgloss.NewStyle().
		Foreground(dimColor).
		Italic(true).
		Width(m.width - 4).
		Align(lipgloss.Center).
		Render("Cardinal v1.0 • Use Tab/1-4 to navigate • q to quit")

	return footer
}

// Helper functions for chart calculations
func getMaxRate(rates []float64) float64 {
	if len(rates) == 0 {
		return 0
	}
	max := rates[0]
	for _, rate := range rates {
		if rate > max {
			max = rate
		}
	}
	return max
}

func getAvgRate(rates []float64) float64 {
	if len(rates) == 0 {
		return 0
	}
	sum := 0.0
	for _, rate := range rates {
		sum += rate
	}
	return sum / float64(len(rates))
}

// Helper function to format duration nicely
func formatDuration(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%.0fs", d.Seconds())
	}
	if d < time.Hour {
		return fmt.Sprintf("%.0fm %.0fs", d.Minutes(), float64(d.Seconds())-(d.Minutes()*60))
	}
	return fmt.Sprintf("%.0fh %.0fm", d.Hours(), d.Minutes()-(d.Hours()*60))
}

// Helper function to render ASCII sparkline chart
func renderSparkline(data []float64) string {
	if len(data) == 0 {
		return "No data"
	}

	// Find min/max for normalization
	min, max := data[0], data[0]
	for _, v := range data {
		if v < min {
			min = v
		}
		if v > max {
			max = v
		}
	}

	// Sparkline characters (from low to high)
	chars := []rune{'▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'}

	var result strings.Builder
	for _, v := range data {
		// Normalize value to 0-7 range
		normalized := 0
		if max > min {
			normalized = int(((v - min) / (max - min)) * 7)
		}
		if normalized > 7 {
			normalized = 7
		}
		result.WriteRune(chars[normalized])
	}

	return lipgloss.NewStyle().
		Foreground(lipgloss.Color("#4ECDC4")).
		Render(result.String()) +
		lipgloss.NewStyle().
			Foreground(lipgloss.Color("#6E7681")).
			Render(fmt.Sprintf(" (%.1f - %.1f msg/s)", min, max))
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
	fmt.Println("🚀 Starting Cardinal - Enhanced TUI with Tabs")

	// Try real Fast DDS first, fallback to mock
	realPub, realSub, err := NewRealDDSSystem(0, "hello_topic")
	if err != nil {
		// Fallback to mock DDS
		fmt.Println("⚠️  Real DDS failed, using mock DDS:", err)
		pub, sub := NewDDSSystem()
		runApplication(pub, sub, false)
	} else {
		fmt.Println("✅ Using real Fast DDS!")

		// Cleanup real DDS on exit
		defer realPub.Cleanup()
		defer realSub.Cleanup()

		runApplication(realPub, realSub, true)
	}
}

func runApplication(pub DDSPublisher, sub DDSSubscriber, usingReal bool) {
	// Initialize spinner
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("#00D7FF"))

	// Initialize progress bars
	prog := progress.New(progress.WithDefaultGradient())
	connBar := progress.New(progress.WithDefaultGradient())

	// Create TUI model
	m := model{
		messages:        []DDSMessage{},
		metrics:         SystemMetrics{ConnectionStatus: "Initializing..."},
		startTime:       time.Now(),
		spinner:         s,
		progressBar:     prog,
		connectionBar:   connBar,
		messageRateHist: []float64{},
		usingRealDDS:    usingReal,
		activeTab:       0, // Start with Dashboard tab
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
