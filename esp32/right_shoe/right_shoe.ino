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
#define MQ135_PIN 34       // Analog (Potentiometer / Gas Sensor)
#define FSR_TOE_PIN 35     // Analog (Toe FSR Potentiometer)
#define FSR_HEEL_PIN 32    // Analog (Heel FSR Potentiometer)
#define FSR_MID_PIN 33     // Analog (Midfoot FSR Potentiometer)
#define RELAY_SHOE_UVC 18  // Digital (Relay / LED Indicator)
#define DHT_PIN 4          // Digital (DHT22 Temp & Humidity)
#define DHT_TYPE DHT22

// Simulation Demo Mode: Set to true if you want 10-second fast cycles during Wokwi testing
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
bool isSterilizing = false;
unsigned long sterilizationStartTime = 0;
unsigned long sterilizationDuration = SIMULATION_FAST_MODE ? 15000 : 300000; // 5 mins default

bool lastFootDetected = false;
unsigned long lastFirebaseUpdate = 0;
unsigned long lastCommandCheck = 0;

const String basePath = String("/devices/") + SYSTEM_ID + "/right_shoe";

// Helper function to turn relay on/off safely
void setShoeRelay(bool state) {
  digitalWrite(RELAY_SHOE_UVC, state ? RELAY_ON : RELAY_OFF);
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n--- SteriStep Right Shoe (Wokwi Simulation) Initializing ---");

  // Relay initialization
  pinMode(RELAY_SHOE_UVC, OUTPUT);
  setShoeRelay(false);

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

  Serial.println("Firebase initialized with Database Secret. Connecting...");
  Serial.println("Right Shoe setup completed successfully.");
}

void loop() {
  unsigned long currentMillis = millis();

  // 1. Read FSR Pressure Sensors (Scaled to 0 - 100 kPa for App Heatmap)
  double rawToe = analogRead(FSR_TOE_PIN);
  double rawHeel = analogRead(FSR_HEEL_PIN);
  double rawMid = analogRead(FSR_MID_PIN);

  double toeP = (rawToe / 4095.0) * 100.0;
  double heelP = (rawHeel / 4095.0) * 100.0;
  double midP = (rawMid / 4095.0) * 100.0;

  if (toeP < 1.0) toeP = 0.0;
  if (heelP < 1.0) heelP = 0.0;
  if (midP < 1.0) midP = 0.0;

  // Foot detected when pressure exceeds threshold (> 8 kPa)
  bool currentFootDetected = (toeP > 8.0 || heelP > 8.0 || midP > 8.0);

  // 2. Flowchart Auto-Sterilization Logic
  if (currentFootDetected && !lastFootDetected) {
    lastFootDetected = true;
    Serial.println("Right Shoe: Foot placed in shoe.");
    pushTelemetryToFirebase(toeP, heelP, midP, currentFootDetected);
  }
  else if (!currentFootDetected && lastFootDetected) {
    lastFootDetected = false;
    Serial.println("Right Shoe: Foot removed! Auto-sterilization starting.");

    if (!isSterilizing) {
      isSterilizing = true;
      setShoeRelay(true);
      sterilizationStartTime = currentMillis;

      // Duration decision based on Humidity (Flowchart specification)
      float h = dht.readHumidity();
      if (!isnan(h) && h >= 65.0) {
        sterilizationDuration = SIMULATION_FAST_MODE ? 10000 : 180000; // 3 minutes (180s)
        Serial.println("High humidity detected (>=65%). Duration: 180s");
      } else {
        sterilizationDuration = SIMULATION_FAST_MODE ? 15000 : 300000; // 5 minutes (300s)
        Serial.println("Normal humidity. Duration: 300s");
      }
      pushTelemetryToFirebase(toeP, heelP, midP, currentFootDetected);
    }
  }

  // 3. Sterilization Timer Check
  if (isSterilizing) {
    if (currentMillis - sterilizationStartTime >= sterilizationDuration) {
      isSterilizing = false;
      setShoeRelay(false);
      Serial.println("Right Shoe: Sterilization cycle finished.");
      pushTelemetryToFirebase(toeP, heelP, midP, currentFootDetected);
    }
  }

  // 4. Non-blocking App Command Checker (Every 1000ms)
  if (currentMillis - lastCommandCheck >= 1000) {
    lastCommandCheck = currentMillis;

    if (WiFi.status() == WL_CONNECTED && Firebase.ready()) {
      if (Firebase.RTDB.getString(&fbDataCommand, basePath + "/command")) {
        String cmd = fbDataCommand.stringData();
        cmd.trim();

        if (cmd == "START_SHOE_UVC" && !isSterilizing) {
          Serial.println("Right Shoe: Received START_SHOE_UVC command from app.");
          isSterilizing = true;
          setShoeRelay(true);
          sterilizationStartTime = currentMillis;
          sterilizationDuration = SIMULATION_FAST_MODE ? 10000 : 180000; // 3 mins
          Firebase.RTDB.setString(&fbDataCommand, basePath + "/command", "IDLE");
          pushTelemetryToFirebase(toeP, heelP, midP, currentFootDetected);
        } else if (cmd == "STOP_SHOE_UVC" || cmd == "STOP" || cmd == "CANCEL") {
          Serial.println("Right Shoe: Received STOP command from app.");
          isSterilizing = false;
          setShoeRelay(false);
          Firebase.RTDB.setString(&fbDataCommand, basePath + "/command", "IDLE");
          pushTelemetryToFirebase(toeP, heelP, midP, currentFootDetected);
        }
      }
    }
  }

  // 5. Periodic Firebase Telemetry Update (Every 3000ms)
  if (currentMillis - lastFirebaseUpdate >= 3000) {
    lastFirebaseUpdate = currentMillis;
    pushTelemetryToFirebase(toeP, heelP, midP, currentFootDetected);
  }
}

void pushTelemetryToFirebase(double toeP, double heelP, double midP, bool footDetected) {
  if (WiFi.status() != WL_CONNECTED || !Firebase.ready()) {
    return;
  }

  int gasAnalog = analogRead(MQ135_PIN);
  if (gasAnalog < 50) gasAnalog = 0;

  float t = dht.readTemperature();
  float h = dht.readHumidity();
  if (isnan(t)) t = 0.0;
  if (isnan(h)) h = 0.0;

  // Push all sensor values using FirebaseJson for single atomic update
  FirebaseJson json;
  json.set("gasAnalog", gasAnalog);
  json.set("toePressure", toeP);
  json.set("heelPressure", heelP);
  json.set("midfootPressure", midP);
  json.set("footDetected", footDetected);
  json.set("isSterilizing", isSterilizing);
  json.set("temperatureC", t);
  json.set("humidityPct", h);
  json.set("uptime", (int)(millis() / 1000));

  if (Firebase.RTDB.updateNode(&fbDataUpdate, basePath, &json)) {
    Serial.println("Right Shoe: Firebase update SUCCESS (Gas: " + String(gasAnalog) + 
                   ", Temp: " + String(t, 1) + "C, Hum: " + String(h, 0) + 
                   "%, Sterilizing: " + String(isSterilizing ? "YES" : "NO") + ")");
  } else {
    Serial.println("Right Shoe: Firebase update FAILED -> " + fbDataUpdate.errorReason());
  }
}
