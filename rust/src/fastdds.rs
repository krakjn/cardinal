use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_long, c_void};
use std::ptr;
use std::sync::{Arc, Mutex};
use std::collections::VecDeque;
use anyhow::{Result, anyhow};
use chrono::{DateTime, Utc};

// FFI bindings to the C interface
#[repr(C)]
pub struct SimpleMessage {
    pub message: [c_char; 256],
    pub timestamp: c_long,
}

pub type SimpleDDSPublisher = *mut c_void;
pub type SimpleDDSSubscriber = *mut c_void;

#[link(name = "cardinal-fastdds", kind = "static")]
#[link(name = "fastdds")]
#[link(name = "fastcdr")]
#[link(name = "stdc++")]
extern "C" {
    fn create_simple_publisher(topic_name: *const c_char) -> SimpleDDSPublisher;
    fn publish_simple_message(pub_: SimpleDDSPublisher, message: *const c_char, timestamp: c_long) -> c_int;
    fn destroy_simple_publisher(pub_: SimpleDDSPublisher);
    
    fn create_simple_subscriber(topic_name: *const c_char) -> SimpleDDSSubscriber;
    fn receive_simple_message(sub: SimpleDDSSubscriber, msg: *mut SimpleMessage) -> c_int;
    fn destroy_simple_subscriber(sub: SimpleDDSSubscriber);
}

#[derive(Debug, Clone)]
pub struct DDSMessage {
    pub content: String,
    pub timestamp: DateTime<Utc>,
}

impl DDSMessage {
    pub fn new(content: String) -> Self {
        Self {
            content,
            timestamp: Utc::now(),
        }
    }
}

pub struct DDSPublisher {
    inner: SimpleDDSPublisher,
}

impl DDSPublisher {
    pub fn new(topic: &str) -> Result<Self> {
        let topic_cstr = CString::new(topic)?;
        let publisher = unsafe { create_simple_publisher(topic_cstr.as_ptr()) };
        
        if publisher.is_null() {
            return Err(anyhow!("Failed to create DDS publisher"));
        }
        
        Ok(Self { inner: publisher })
    }
    
    pub fn publish(&self, message: &DDSMessage) -> Result<()> {
        let content_cstr = CString::new(message.content.clone())?;
        let timestamp = message.timestamp.timestamp();
        
        let result = unsafe {
            publish_simple_message(self.inner, content_cstr.as_ptr(), timestamp as c_long)
        };
        
        if result != 0 {
            return Err(anyhow!("Failed to publish message"));
        }
        
        Ok(())
    }
}

impl Drop for DDSPublisher {
    fn drop(&mut self) {
        if !self.inner.is_null() {
            unsafe { destroy_simple_publisher(self.inner) };
        }
    }
}

unsafe impl Send for DDSPublisher {}
unsafe impl Sync for DDSPublisher {}

pub struct DDSSubscriber {
    inner: SimpleDDSSubscriber,
}

impl DDSSubscriber {
    pub fn new(topic: &str) -> Result<Self> {
        let topic_cstr = CString::new(topic)?;
        let subscriber = unsafe { create_simple_subscriber(topic_cstr.as_ptr()) };
        
        if subscriber.is_null() {
            return Err(anyhow!("Failed to create DDS subscriber"));
        }
        
        Ok(Self { inner: subscriber })
    }
    
    pub fn receive(&self) -> Option<DDSMessage> {
        let mut c_msg = SimpleMessage {
            message: [0; 256],
            timestamp: 0,
        };
        
        let result = unsafe {
            receive_simple_message(self.inner, &mut c_msg as *mut SimpleMessage)
        };
        
        if result == 0 {
            let c_str = unsafe { CStr::from_ptr(c_msg.message.as_ptr()) };
            if let Ok(content) = c_str.to_str() {
                let timestamp = DateTime::from_timestamp(c_msg.timestamp, 0)
                    .unwrap_or_else(Utc::now);
                
                return Some(DDSMessage {
                    content: content.to_string(),
                    timestamp,
                });
            }
        }
        
        None
    }
}

impl Drop for DDSSubscriber {
    fn drop(&mut self) {
        if !self.inner.is_null() {
            unsafe { destroy_simple_subscriber(self.inner) };
        }
    }
}

unsafe impl Send for DDSSubscriber {}
unsafe impl Sync for DDSSubscriber {}

// Mock DDS system for fallback
#[derive(Clone)]
pub struct MockDDSSystem {
    messages: Arc<Mutex<VecDeque<DDSMessage>>>,
}

impl MockDDSSystem {
    pub fn new() -> Self {
        Self {
            messages: Arc::new(Mutex::new(VecDeque::new())),
        }
    }
    
    pub fn create_publisher(&self) -> MockPublisher {
        MockPublisher {
            system: self.clone(),
        }
    }
    
    pub fn create_subscriber(&self) -> MockSubscriber {
        MockSubscriber {
            system: self.clone(),
        }
    }
}

pub struct MockPublisher {
    system: MockDDSSystem,
}

impl MockPublisher {
    pub fn publish(&self, message: &DDSMessage) -> Result<()> {
        if let Ok(mut messages) = self.system.messages.lock() {
            messages.push_back(message.clone());
            // Keep only last 100 messages
            if messages.len() > 100 {
                messages.pop_front();
            }
        }
        Ok(())
    }
}

pub struct MockSubscriber {
    system: MockDDSSystem,
}

impl MockSubscriber {
    pub fn receive(&self) -> Option<DDSMessage> {
        if let Ok(mut messages) = self.system.messages.lock() {
            messages.pop_front()
        } else {
            None
        }
    }
}