#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include <DHT.h>
// Include Firebase ESP32 library (Install "Firebase ESP32 Client" by Mobizt in Arduino IDE)
#include <FirebaseESP32.h>

// ==========================================
// WIFI & FIREBASE CONFIGURATION
// ==========================================
#define WIFI_SSID "BELL4G"
#define WIFI_PASSWORD "Brothers123"

#define FIREBASE_HOST "sterstep-cfeed-default-rtdb.firebaseio.com"
#define FIREBASE_AUTH "krvZo8Lp9460s5p9parhlRVFAecENffjzd8rl0zp"

// ==========================================
// PIN CONFIGURATION (UPDATED FOR ESP32-S3)
// ==========================================
// ESP32-S3 ADC pins are GPIO 1-20. 
#define MQ135_PIN 1        // Analog input for Gas Sensor (ADC1_CH0)
#define FSR_TOE_PIN 2      // Analog input for Toe Pressure (ADC1_CH1)
#define FSR_HEEL_PIN 3     // Analog input for Heel Pressure (ADC1_CH2)
#define FSR_MID_PIN 4      // Analog input for Midfoot Pressure (ADC1_CH3)
#define DHT_PIN 5          // Digital pin for DHT22
#define DHT_TYPE DHT22     

#define RELAY_UVC 6        // Relay 1: UVC Light
#define RELAY_MIST 7       // Relay 2: H2O2 Mist Maker
#define RELAY_FAN 8        // Relay 3: Circulation Fan
#define REED_SWITCH 9      // Digital input: Door sensor (LOW = closed)
#define BUZZER_PIN 10      // Digital output: Buzzer

DHT dht(DHT_PIN, DHT_TYPE);
WebServer server(80);
FirebaseData firebaseData;
FirebaseAuth auth;
FirebaseConfig config;

// ==========================================
// STATE VARIABLES
// ==========================================
String cabinetStatus = "Idle";
unsigned long lastFirebaseUpdate = 0;

void setup() {
  Serial.begin(115200);
  
  // Initialize Pins
  pinMode(RELAY_UVC, OUTPUT);
  pinMode(RELAY_MIST, OUTPUT);
  pinMode(RELAY_FAN, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(REED_SWITCH, INPUT_PULLUP);
  
  // Ensure relays are OFF initially (assuming active LOW, change if active HIGH)
  digitalWrite(RELAY_UVC, HIGH); 
  digitalWrite(RELAY_MIST, HIGH);
  digitalWrite(RELAY_FAN, HIGH);
  digitalWrite(BUZZER_PIN, LOW);
  
  dht.begin();
  
  // Connect to WiFi
  Serial.print("Connecting to WiFi: ");
  Serial.println(WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected!");
  Serial.print("ESP32 IP Address: ");
  Serial.println(WiFi.localIP());

  // Configure Firebase
  Serial.println("Connecting to Firebase...");
  config.host = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  if (Firebase.ready()) {
    Serial.println("Firebase Connected Successfully! 🎉");
  } else {
    Serial.println("Firebase Connection Started. Waiting to verify...");
  }

  // Setup Web Server Routes (Optional, can be removed later)
  server.on("/sensors", HTTP_GET, handleGetSensors);
  server.begin();
  Serial.println("System Ready! Pushing data to cloud...");
}

void loop() {
  server.handleClient();
  
  // Process Sterilization Logic (Simplified safety check)
  bool isDoorClosed = digitalRead(REED_SWITCH) == LOW;
  int gasValue = analogRead(MQ135_PIN);
  
  if (!isDoorClosed && (cabinetStatus == "UVC Sterilizing" || cabinetStatus == "UVC+H2O2 Sterilizing")) {
    // Safety abort!
    digitalWrite(RELAY_UVC, HIGH); // Turn OFF
    digitalWrite(RELAY_MIST, HIGH); // Turn OFF
    cabinetStatus = "Door Open Warning";
    tone(BUZZER_PIN, 1000, 500); // Alert buzzer
  }

  // Update Firebase every 5 seconds
  if (millis() - lastFirebaseUpdate > 5000) {
    updateFirebase();
    lastFirebaseUpdate = millis();
  }
}

void handleGetSensors() {
  // Read Sensors
  int gasAnalog = analogRead(MQ135_PIN);
  
  // FSR conversion to approximate kPa (simplified mapping)
  double toeP = analogRead(FSR_TOE_PIN) * (10.0 / 4095.0); 
  double heelP = analogRead(FSR_HEEL_PIN) * (10.0 / 4095.0);
  double midP = analogRead(FSR_MID_PIN) * (10.0 / 4095.0);
  
  double t = dht.readTemperature();
  double h = dht.readHumidity();
  
  if (isnan(t)) t = 0;
  if (isnan(h)) h = 0;
  
  bool footDetected = (toeP > 1.0 || heelP > 1.0);

  // Determine automatic cabinet status if idle
  if (cabinetStatus == "Idle") {
    if (gasAnalog > 2500) {
       cabinetStatus = "UVC+H2O2 Sterilizing"; // Logic can be expanded for timers
    } else if (gasAnalog > 1200) {
       cabinetStatus = "UVC Sterilizing";
    }
  }

  // Create JSON Response
  StaticJsonDocument<500> json;
  json["gasAnalog"] = gasAnalog;
  json["toePressure"] = toeP;
  json["heelPressure"] = heelP;
  json["midfootPressure"] = midP;
  json["temperatureC"] = t;
  json["humidityPct"] = h;
  json["footDetected"] = footDetected;
  json["cabinetStatus"] = cabinetStatus;

  String jsonString;
  serializeJson(json, jsonString);
  
  server.send(200, "application/json", jsonString);
}

void updateFirebase() {
  int gasAnalog = analogRead(MQ135_PIN);
  double t = dht.readTemperature();
  double h = dht.readHumidity();
  
  if (isnan(t)) t = 0;
  if (isnan(h)) h = 0;
  
  // FSR conversion
  double toeP = analogRead(FSR_TOE_PIN) * (10.0 / 4095.0); 
  double heelP = analogRead(FSR_HEEL_PIN) * (10.0 / 4095.0);
  double midP = analogRead(FSR_MID_PIN) * (10.0 / 4095.0);
  bool footDetected = (toeP > 1.0 || heelP > 1.0);

  // Push data to Realtime Database under a specific device ID
  String basePath = "/steristep/device_1";
  
  bool success = true;
  success &= Firebase.setInt(firebaseData, basePath + "/gasAnalog", gasAnalog);
  success &= Firebase.setFloat(firebaseData, basePath + "/temperatureC", t);
  success &= Firebase.setFloat(firebaseData, basePath + "/humidityPct", h);
  success &= Firebase.setFloat(firebaseData, basePath + "/toePressure", toeP);
  success &= Firebase.setFloat(firebaseData, basePath + "/heelPressure", heelP);
  success &= Firebase.setFloat(firebaseData, basePath + "/midfootPressure", midP);
  success &= Firebase.setBool(firebaseData, basePath + "/footDetected", footDetected);
  success &= Firebase.setString(firebaseData, basePath + "/cabinetStatus", cabinetStatus);
  success &= Firebase.setInt(firebaseData, basePath + "/uptime", millis() / 1000); // Heartbeat for Flutter app


  if (success) {
    Serial.println("Firebase update SUCCESS!");
  } else {
    Serial.print("Firebase update FAILED. Error: ");
    Serial.println(firebaseData.errorReason());
  }
}
