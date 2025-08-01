use std::sync::{Arc, Mutex, MutexGuard};
use std::collections::VecDeque;
use std::time::{Duration, Instant};
use ratatui::{
    backend::Backend,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    symbols::border,
    text::{Line, Span, Text},
    widgets::{Block, Borders, Clear, List, ListItem, Paragraph, Wrap},
    Frame, Terminal,
};
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use anyhow::Result;
use chrono::{DateTime, Utc};

use crate::fastdds::DDSMessage;

pub struct App {
    messages: Arc<Mutex<VecDeque<DDSMessage>>>,
    should_quit: bool,
    last_update: Instant,
    status: String,
}

impl App {
    pub fn new(messages: Arc<Mutex<VecDeque<DDSMessage>>>) -> Self {
        Self {
            messages,
            should_quit: false,
            last_update: Instant::now(),
            status: "Starting Cardinal...".to_string(),
        }
    }
    
    pub fn set_status(&mut self, status: String) {
        self.status = status;
    }
    
    pub fn should_quit(&self) -> bool {
        self.should_quit
    }
    
    pub fn handle_events(&mut self) -> Result<()> {
        if event::poll(Duration::from_millis(50))? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Press {
                    match key.code {
                        KeyCode::Char('q') | KeyCode::Esc => {
                            self.should_quit = true;
                        }
                        KeyCode::Char('c') if key.modifiers.contains(crossterm::event::KeyModifiers::CONTROL) => {
                            self.should_quit = true;
                        }
                        _ => {}
                    }
                }
            }
        }
        Ok(())
    }
    
    pub fn draw(&mut self, f: &mut Frame) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .margin(1)
            .constraints([
                Constraint::Length(3), // Title
                Constraint::Min(10),   // Messages
                Constraint::Length(3), // Status
                Constraint::Length(2), // Help
            ])
            .split(f.size());
        
        // Title
        let title = Paragraph::new("🚀 Cardinal - Fast DDS + Ratatui Demo")
            .style(Style::default()
                .fg(Color::White)
                .bg(Color::Magenta)
                .add_modifier(Modifier::BOLD))
            .alignment(Alignment::Center)
            .block(Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Magenta)));
        f.render_widget(title, chunks[0]);
        
        // Messages
        let messages_block = Block::default()
            .title("📨 DDS Messages")
            .title_style(Style::default().fg(Color::Green).add_modifier(Modifier::BOLD))
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Green));
        
        let messages: Vec<ListItem> = if let Ok(msg_queue) = self.messages.lock() {
            msg_queue.iter().map(|msg| {
                let time_str = msg.timestamp.format("%H:%M:%S").to_string();
                let line = Line::from(vec![
                    Span::styled(
                        format!("[{}] ", time_str),
                        Style::default().fg(Color::Gray).add_modifier(Modifier::ITALIC)
                    ),
                    Span::styled(
                        "• ",
                        Style::default().fg(Color::Green)
                    ),
                    Span::styled(
                        msg.content.clone(),
                        Style::default().fg(Color::Cyan)
                    ),
                ]);
                ListItem::new(line)
            }).collect()
        } else {
            vec![ListItem::new(Line::from(Span::styled(
                "Loading messages...",
                Style::default().fg(Color::Yellow)
            )))]
        };
        
        let messages_list = List::new(messages)
            .block(messages_block)
            .style(Style::default().fg(Color::White));
        f.render_widget(messages_list, chunks[1]);
        
        // Status
        let status_text = if self.last_update.elapsed() < Duration::from_secs(1) {
            format!("🟢 {} (Active)", self.status)
        } else {
            format!("🟡 {} (Idle)", self.status)
        };
        
        let status = Paragraph::new(status_text)
            .style(Style::default().fg(Color::White))
            .alignment(Alignment::Left)
            .block(Block::default()
                .title("Status")
                .title_style(Style::default().fg(Color::Blue))
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Blue)));
        f.render_widget(status, chunks[2]);
        
        // Help
        let help = Paragraph::new("Press 'q' or Ctrl+C to quit")
            .style(Style::default().fg(Color::Gray))
            .alignment(Alignment::Center);
        f.render_widget(help, chunks[3]);
    }
    
    pub fn update(&mut self) {
        self.last_update = Instant::now();
    }
}

pub fn setup_terminal() -> Result<Terminal<ratatui::backend::CrosstermBackend<std::io::Stdout>>> {
    enable_raw_mode()?;
    let mut stdout = std::io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = ratatui::backend::CrosstermBackend::new(stdout);
    let terminal = Terminal::new(backend)?;
    Ok(terminal)
}

pub fn restore_terminal(
    terminal: &mut Terminal<ratatui::backend::CrosstermBackend<std::io::Stdout>>,
) -> Result<()> {
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;
    Ok(())
}