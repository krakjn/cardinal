mod fastdds;
mod tui;

use std::sync::{Arc, Mutex};
use std::collections::VecDeque;
use std::time::{Duration, Instant};
use tokio::time::sleep;
use anyhow::Result;
use tracing::{info, warn, error};

use fastdds::{DDSMessage, DDSPublisher, DDSSubscriber, MockDDSSystem};
use tui::{App, setup_terminal, restore_terminal};

async fn publisher_task(
    publisher: Arc<dyn Publisher + Send + Sync>,
    messages: Arc<Mutex<VecDeque<DDSMessage>>>,
) {
    let mut counter = 0;
    let mut interval = tokio::time::interval(Duration::from_secs(2));
    
    loop {
        interval.tick().await;
        counter += 1;
        
        let message = DDSMessage::new(format!("Hello World #{}", counter));
        
        match publisher.publish(&message).await {
            Ok(_) => {
                info!("📤 Published: {}", message.content);
                
                // Add to display queue for immediate feedback
                if let Ok(mut msg_queue) = messages.lock() {
                    msg_queue.push_back(message);
                    if msg_queue.len() > 20 {
                        msg_queue.pop_front();
                    }
                }
            }
            Err(e) => {
                error!("❌ Error publishing: {}", e);
            }
        }
    }
}

async fn subscriber_task(
    subscriber: Arc<dyn Subscriber + Send + Sync>,
    messages: Arc<Mutex<VecDeque<DDSMessage>>>,
) {
    let mut interval = tokio::time::interval(Duration::from_millis(10));
    
    loop {
        interval.tick().await;
        
        if let Some(message) = subscriber.receive().await {
            info!("📨 Received: {}", message.content);
            
            if let Ok(mut msg_queue) = messages.lock() {
                msg_queue.push_back(message);
                if msg_queue.len() > 20 {
                    msg_queue.pop_front();
                }
            }
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();
    
    info!("🚀 Starting Cardinal Rust - Fast DDS + Ratatui Demo");
    
    // Shared message queue for TUI display
    let messages: Arc<Mutex<VecDeque<DDSMessage>>> = Arc::new(Mutex::new(VecDeque::new()));
    
    // Try real Fast DDS first, fallback to mock
    let (publisher, subscriber, status) = match create_real_dds_system().await {
        Ok((pub_, sub)) => {
            info!("✅ Using real Fast DDS!");
            (pub_, sub, "Using real Fast DDS".to_string())
        }
        Err(e) => {
            warn!("⚠️  Real DDS failed: {}, using mock DDS", e);
            let (pub_, sub) = create_mock_dds_system().await;
            (pub_, sub, "Using mock DDS (Fast DDS failed)".to_string())
        }
    };
    
    // Setup terminal
    let mut terminal = setup_terminal()?;
    let mut app = App::new(messages.clone());
    app.set_status(status);
    
    // Spawn background tasks
    let messages_clone = messages.clone();
    let publisher_handle = tokio::spawn(publisher_task(publisher, messages_clone));
    
    let messages_clone = messages.clone();
    let subscriber_handle = tokio::spawn(subscriber_task(subscriber, messages_clone));
    
    // Main UI loop
    let result = run_ui(&mut terminal, &mut app).await;
    
    // Cleanup
    publisher_handle.abort();
    subscriber_handle.abort();
    restore_terminal(&mut terminal)?;
    
    match result {
        Ok(_) => info!("Cardinal application terminated successfully."),
        Err(e) => error!("Application error: {}", e),
    }
    
    Ok(())
}

async fn run_ui(
    terminal: &mut ratatui::Terminal<ratatui::backend::CrosstermBackend<std::io::Stdout>>,
    app: &mut App,
) -> Result<()> {
    while !app.should_quit() {
        terminal.draw(|f| app.draw(f))?;
        app.handle_events()?;
        app.update();
        sleep(Duration::from_millis(50)).await;
    }
    Ok(())
}

// Trait for abstracting publisher/subscriber
#[async_trait::async_trait]
trait Publisher {
    async fn publish(&self, message: &DDSMessage) -> Result<()>;
}

#[async_trait::async_trait]
trait Subscriber {
    async fn receive(&self) -> Option<DDSMessage>;
}

// Real DDS implementations
struct RealDDSPublisher {
    inner: DDSPublisher,
}

#[async_trait::async_trait]
impl Publisher for RealDDSPublisher {
    async fn publish(&self, message: &DDSMessage) -> Result<()> {
        self.inner.publish(message)
    }
}

struct RealDDSSubscriber {
    inner: DDSSubscriber,
}

#[async_trait::async_trait]
impl Subscriber for RealDDSSubscriber {
    async fn receive(&self) -> Option<DDSMessage> {
        self.inner.receive()
    }
}

// Mock DDS implementations
struct MockPublisher {
    inner: fastdds::MockPublisher,
}

#[async_trait::async_trait]
impl Publisher for MockPublisher {
    async fn publish(&self, message: &DDSMessage) -> Result<()> {
        self.inner.publish(message)
    }
}

struct MockSubscriber {
    inner: fastdds::MockSubscriber,
}

#[async_trait::async_trait]
impl Subscriber for MockSubscriber {
    async fn receive(&self) -> Option<DDSMessage> {
        self.inner.receive()
    }
}

async fn create_real_dds_system() -> Result<(Arc<dyn Publisher + Send + Sync>, Arc<dyn Subscriber + Send + Sync>)> {
    let publisher = DDSPublisher::new("hello_topic")?;
    let subscriber = DDSSubscriber::new("hello_topic")?;
    
    Ok((
        Arc::new(RealDDSPublisher { inner: publisher }),
        Arc::new(RealDDSSubscriber { inner: subscriber }),
    ))
}

async fn create_mock_dds_system() -> (Arc<dyn Publisher + Send + Sync>, Arc<dyn Subscriber + Send + Sync>) {
    let mock_system = MockDDSSystem::new();
    
    let publisher = mock_system.create_publisher();
    let subscriber = mock_system.create_subscriber();
    
    (
        Arc::new(MockPublisher { inner: publisher }),
        Arc::new(MockSubscriber { inner: subscriber }),
    )
}