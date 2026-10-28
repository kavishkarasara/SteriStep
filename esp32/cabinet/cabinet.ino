#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <DHT.h>

// Firebase Addons
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

// ==========================================
// WIFI & FIREBASE CONFIGURATION (Wokwi & App)
// ==========================================
#define WIFI_SSID "Wokwi-GUEST"
#define WIFI_PASSWORD ""

#define API_KEY "AIzaSyCEFsgDZh_FNc1BEoRw6bPfXdfx5sTwWd8"
#define DATABASE_URL "https://sterstep-cfeed-default-rtdb.firebaseio.com/"
#define DATABASE_SECRET "krvZo8Lp9460s5p9parhlRVFAecENffjzd8rl0zp" // Firebase Database Secret
#define SYSTEM_ID "steristep_001" // Unique Device ID

// ==========================================
// PIN DEFINITIONS (Wokwi ESP32 Safe Pins)
// ==========================================
#define DHT_PIN 4          // Digital (DHT22 Temp & Humidity)
#define DHT_TYPE DHT22

#define RELAY_UVC 18       // Digital Output (Relay UVC / Purple LED)
#define RELAY_MIST 19      // Digital Output (Relay H2O2 Mist / Blue LED)
#define RELAY_FAN 21       // Digital Output (Relay Fan / Green LED)
#define REED_SWITCH 22     // Digital Input (Door Switch: 0 = Closed, 1 = Open, INPUT_PULLUP)
#define BUZZER_PIN 23      // Digital Output (Piezo Buzzer)

// Simulation Demo Mode: Set to true if you want 15-20 second fast cycles during Wokwi testing
#define SIMULATION_FAST_MODE false

// Relay logic level (Active-HIGH)
#define RELAY_ACTIVE_HIGH true
#define RELAY_ON  (RELAY_ACTIVE_HIGH ? HIGH : LOW)
#define RELAY_OFF (RELAY_ACTIVE_HIGH ? LOW : HIGH)

// ==========================================
// HARDWARE OBJECTS & TIMERS
// ==========================================
DHT dht(DHT_PIN, DHT_TYPE);
FirebaseData fbDataCommand;
FirebaseData fbDataUpdate;
FirebaseAuth auth;
FirebaseConfig config;

// State variables
String cabinetStatus = "Idle";
bool isSterilizing = false;
bool isPausedForDoor = false;
unsigned long sterilizationStartTime = 0;
unsigned long elapsedActiveTime = 0;
unsigned long totalCycleDuration = SIMULATION_FAST_MODE ? 15000 : 900000; // 15 mins default
int sterilizationProgress = 0;

unsigned long lastFirebaseUpdate = 0;
unsigned long lastCommandCheck = 0;
unsigned long lastLoopTimestamp = 0;
unsigned long lastDoorBeepTime = 0;

const String basePath = String("/devices/") + SYSTEM_ID + "/cabinet";

// Helper functions for actuators
void setAllRelaysOff() {
  digitalWrite(RELAY_UVC, RELAY_OFF);
  digitalWrite(RELAY_MIST, RELAY_OFF);
  digitalWrite(RELAY_FAN, RELAY_OFF);
}

void beepBuzzer(int count, int onTimeMs, int offTimeMs) {
  for (int i = 0; i < count; i++) {
    digitalWrite(BUZZER_PIN, HIGH);
    delay(onTimeMs);
    digitalWrite(BUZZER_PIN, LOW);
    if (i < count - 1) delay(offTimeMs);
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n--- SteriStep Cabinet (Wokwi Simulation) Initializing ---");

  // Actuator pin modes
  pinMode(RELAY_UVC, OUTPUT);
  pinMode(RELAY_MIST, OUTPUT);
  pinMode(RELAY_FAN, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  setAllRelaysOff();

  // Door Reed Switch with internal pullup
  pinMode(REED_SWITCH, INPUT_PULLUP);

  // Initialize DHT22
  dht.begin();
  Serial.println("DHT22 Sensor initialized.");

  // Connect to WiFi (Wokwi-GUEST)
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to Wokwi WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected! IP: " + WiFi.localIP().toString());

  // Initialize Firebase RTDB using Database Secret (Legacy Token)
  // This bypasses ADMIN_ONLY_OPERATION and grants full Admin read/write permissions directly!
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;
  config.signer.tokens.legacy_token = DATABASE_SECRET;

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  fbDataCommand.setResponseSize(1024);
  fbDataUpdate.setResponseSize(1024);

  lastLoopTimestamp = millis();
  
  // Power on boot chirp
  beepBuzzer(1, 150, 0);

  Serial.println("Firebase initialized with Database Secret. Connecting...");
  Serial.println("Cabinet setup completed successfully.");
}

void loop() {
  unsigned long currentMillis = millis();
  unsigned long loopDelta = currentMillis - lastLoopTimestamp;
  lastLoopTimestamp = currentMillis;

  // 1. Read Door Reed Switch (0 = Closed, 1 = Open)
  int doorStatus = digitalRead(REED_SWITCH);
  bool isDoorOpen = (doorStatus == 1);

  // 2. Non-blocking App Command Checker (Every 1000ms)
  if (currentMillis - lastCommandCheck >= 1000) {
    lastCommandCheck = currentMillis;

    if (WiFi.status() == WL_CONNECTED && Firebase.ready()) {
      if (Firebase.RTDB.getString(&fbDataCommand, basePath + "/command")) {
        String cmd = fbDataCommand.stringData();
        cmd.trim();

        if (cmd == "START_UVC" && !isSterilizing) {
          if (isDoorOpen) {
            Serial.println("Cabinet: Cannot start UVC - Door is OPEN!");
            beepBuzzer(2, 200, 100);
          } else {
            Serial.println("Cabinet: Starting UVC Cycle (15 mins)...");
            isSterilizing = true;
            isPausedForDoor = false;
            cabinetStatus = "UVC Sterilization in process";
            totalCycleDuration = SIMULATION_FAST_MODE ? 15000 : 900000; // 15 mins
            elapsedActiveTime = 0;
            sterilizationProgress = 0;
            sterilizationStartTime = currentMillis;
            Firebase.RTDB.setString(&fbDataCommand, basePath + "/command", "IDLE");
            pushCabinetTelemetry(doorStatus);
          }
        } 
        else if (cmd == "START_HEAVY" && !isSterilizing) {
          if (isDoorOpen) {
            Serial.println("Cabinet: Cannot start Heavy Cycle - Door is OPEN!");
            beepBuzzer(2, 200, 100);
          } else {
            Serial.println("Cabinet: Starting Heavy Cycle UVC + H2O2 (20 mins)...");
            isSterilizing = true;
            isPausedForDoor = false;
            cabinetStatus = "Sterilization in process";
            totalCycleDuration = SIMULATION_FAST_MODE ? 20000 : 1200000; // 20 mins
            elapsedActiveTime = 0;
            sterilizationProgress = 0;
            sterilizationStartTime = currentMillis;
            Firebase.RTDB.setString(&fbDataCommand, basePath + "/command", "IDLE");
            pushCabinetTelemetry(doorStatus);
          }
        }
        else if (cmd == "STOP" || cmd == "CANCEL") {
          Serial.println("Cabinet: Sterilization CANCELLED by user.");
          isSterilizing = false;
          isPausedForDoor = false;
          cabinetStatus = "Idle";
          sterilizationProgress = 0;
          setAllRelaysOff();
          Firebase.RTDB.setString(&fbDataCommand, basePath + "/command", "IDLE");
          pushCabinetTelemetry(doorStatus);
        }
      }
    }
  }

  // 3. Sterilization Cycle & Safety Interlock Logic
  if (isSterilizing) {
    // CRITICAL SAFETY INTERLOCK: If door is opened, shut off UVC and Mist immediately!
    if (isDoorOpen) {
      if (!isPausedForDoor) {
        Serial.println("WARNING: Cabinet door OPENED during sterilization! Safety auto-shutoff activated.");
        isPausedForDoor = true;
        pushCabinetTelemetry(doorStatus);
      }

      // Turn OFF UVC and Mist immediately for human safety!
      digitalWrite(RELAY_UVC, RELAY_OFF);
      digitalWrite(RELAY_MIST, RELAY_OFF);
      // Run FAN to extract any mist/ozone
      digitalWrite(RELAY_FAN, RELAY_ON);

      // Warning beep every 2 seconds
      if (currentMillis - lastDoorBeepTime >= 2000) {
        lastDoorBeepTime = currentMillis;
        digitalWrite(BUZZER_PIN, HIGH);
        delay(100);
        digitalWrite(BUZZER_PIN, LOW);
      }
      // Do not increment elapsedActiveTime while door is open (paused)
    } 
    else {
      // Door is safely closed
      if (isPausedForDoor) {
        Serial.println("Cabinet door closed. Resuming sterilization cycle.");
        isPausedForDoor = false;
        pushCabinetTelemetry(doorStatus);
      }

      // Increment active time
      elapsedActiveTime += loopDelta;

      // Calculate progress percentage (0 - 100%)
      sterilizationProgress = (elapsedActiveTime * 100) / totalCycleDuration;
      if (sterilizationProgress > 100) sterilizationProgress = 100;

      // Actuator control based on cycle type
      if (cabinetStatus == "Sterilization in process") {
        // Heavy Cycle: H2O2 Mist + UVC + Fan together
        digitalWrite(RELAY_UVC, RELAY_ON);
        digitalWrite(RELAY_MIST, RELAY_ON);
        digitalWrite(RELAY_FAN, RELAY_ON);
      } else {
        // Standard Cycle: UVC only + Fan
        digitalWrite(RELAY_UVC, RELAY_ON);
        digitalWrite(RELAY_MIST, RELAY_OFF);
        digitalWrite(RELAY_FAN, RELAY_ON);
      }

      // Check if cycle duration reached
      if (elapsedActiveTime >= totalCycleDuration) {
        Serial.println("Cabinet: Sterilization cycle SUCCESS! Cleaning process is done.");
        isSterilizing = false;
        cabinetStatus = "Cleaning process is done"; // Exact string expected by Flutter app
        sterilizationProgress = 100;
        
        // Turn off all active relays
        setAllRelaysOff();

        // Push completion immediately to Firebase
        pushCabinetTelemetry(doorStatus);

        // 3 celebration beeps for completion
        beepBuzzer(3, 200, 150);
      }
    }
  } else {
    // When idle and door is open, ensure relays stay OFF
    if (cabinetStatus == "Cleaning process is done" && isDoorOpen) {
      cabinetStatus = "Idle";
      sterilizationProgress = 0;
      pushCabinetTelemetry(doorStatus);
    }
  }

  // 4. Periodic Firebase Telemetry Update
  // Update every 2000ms during sterilization (for smooth progress bar), 3500ms when idle
  unsigned long updateInterval = isSterilizing ? 2000 : 3500;
  if (currentMillis - lastFirebaseUpdate >= updateInterval) {
    lastFirebaseUpdate = currentMillis;
    pushCabinetTelemetry(doorStatus);
  }
}

void pushCabinetTelemetry(int doorStatus) {
  if (WiFi.status() != WL_CONNECTED || !Firebase.ready()) {
    return;
  }

  // Read DHT22
  float t = dht.readTemperature();
  float h = dht.readHumidity();
  if (isnan(t)) t = 0.0;
  if (isnan(h)) h = 0.0;

  // Single atomic FirebaseJson update
  FirebaseJson json;
  json.set("temperatureC", t);
  json.set("humidityPct", h);
  json.set("cabinetStatus", cabinetStatus);
  json.set("progress", sterilizationProgress);
  json.set("doorOpen", doorStatus);
  json.set("uptime", (int)(millis() / 1000));

  if (Firebase.RTDB.updateNode(&fbDataUpdate, basePath, &json)) {
    Serial.println("Cabinet: Firebase update SUCCESS (Status: " + cabinetStatus + 
                   ", Progress: " + String(sterilizationProgress) + "%" +
                   ", Door: " + String(doorStatus == 1 ? "OPEN" : "CLOSED") +
                   ", Temp: " + String(t, 1) + "C, Hum: " + String(h, 0) + "%)");
  } else {
    Serial.println("Cabinet: Firebase update FAILED -> " + fbDataUpdate.errorReason());
  }
}
