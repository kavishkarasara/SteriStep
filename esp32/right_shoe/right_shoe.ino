#include <WiFi.h>
#include <FirebaseESP32.h>

#define WIFI_SSID "BELL4G"
#define WIFI_PASSWORD "Brothers123"

#define FIREBASE_HOST "sterstep-cfeed-default-rtdb.firebaseio.com"
#define FIREBASE_AUTH "krvZo8Lp9460s5p9parhlRVFAecENffjzd8rl0zp"
#define SYSTEM_ID "steristep_001" // UNIQUE ID FOR THIS PHYSICAL DEVICE

// Pins for ESP32-S3
#define MQ135_PIN 1
#define FSR_TOE_PIN 2
#define FSR_HEEL_PIN 3
#define FSR_MID_PIN 4
#define RELAY_SHOE_UVC 5

FirebaseData firebaseData;
FirebaseAuth auth;
FirebaseConfig config;

unsigned long lastUpdate = 0;
bool isSterilizing = false;
unsigned long sterilizationStartTime = 0;

void setup() {
  Serial.begin(115200);
  
  pinMode(RELAY_SHOE_UVC, OUTPUT);
  digitalWrite(RELAY_SHOE_UVC, LOW);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected!");

  config.host = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
}

#include <DHT.h>

#define DHT_PIN 6
#define DHT_TYPE DHT22

DHT dht(DHT_PIN, DHT_TYPE);

bool lastFootDetected = false;
unsigned long sterilizationDuration = 300000; // Default 5 mins

void loop() {
  String basePath = String("/devices/") + SYSTEM_ID + "/right_shoe";
  
  // Read Sensors for Auto-Logic
  double toeP = analogRead(FSR_TOE_PIN) * (10.0 / 4095.0); 
  double heelP = analogRead(FSR_HEEL_PIN) * (10.0 / 4095.0);
  bool currentFootDetected = (toeP > 1.0 || heelP > 1.0);

  // Flowchart Auto-Sterilization Logic
  if (currentFootDetected && !lastFootDetected) {
    lastFootDetected = true; // Foot put in
  }
  else if (!currentFootDetected && lastFootDetected) {
    lastFootDetected = false; // Foot removed
    
    if (!isSterilizing) {
      isSterilizing = true;
      digitalWrite(RELAY_SHOE_UVC, HIGH); // H2O2 / UVC Relay
      sterilizationStartTime = millis();
      
      // Determine duration based on Humidity
      float h = dht.readHumidity();
      if (!isnan(h) && h >= 65.0) {
        sterilizationDuration = 180000; // 180s (3 mins)
      } else {
        sterilizationDuration = 300000; // 300s (5 mins)
      }
    }
  }

  // App Command overrides
  if (Firebase.getString(firebaseData, basePath + "/command")) {
    String cmd = firebaseData.stringData();
    if (cmd == "START_SHOE_UVC" && !isSterilizing) {
      isSterilizing = true;
      digitalWrite(RELAY_SHOE_UVC, HIGH);
      sterilizationStartTime = millis();
      sterilizationDuration = 180000; // Manual run for 3 mins
      Firebase.setString(firebaseData, basePath + "/command", "IDLE");
    }
  }

  // Sterilization Timer
  if (isSterilizing) {
    if (millis() - sterilizationStartTime > sterilizationDuration) {
      isSterilizing = false;
      digitalWrite(RELAY_SHOE_UVC, LOW);
    }
  }

  // Push to Firebase every 5s
  if (millis() - lastUpdate >= 5000) {
    lastUpdate = millis();
    updateFirebase();
  }
}

void updateFirebase() {
  int gasAnalog = analogRead(MQ135_PIN);
  if (gasAnalog < 100) gasAnalog = 0; 

  double toeP = analogRead(FSR_TOE_PIN) * (10.0 / 4095.0); 
  if (toeP < 0.2) toeP = 0;
  
  double heelP = analogRead(FSR_HEEL_PIN) * (10.0 / 4095.0);
  if (heelP < 0.2) heelP = 0;
  
  double midP = analogRead(FSR_MID_PIN) * (10.0 / 4095.0);
  if (midP < 0.2) midP = 0;
  bool footDetected = (toeP > 1.0 || heelP > 1.0);

  float t = dht.readTemperature();
  float h = dht.readHumidity();
  if (isnan(t)) t = 0.0;
  if (isnan(h)) h = 0.0;

  String basePath = String("/devices/") + SYSTEM_ID + "/right_shoe";
  
  bool success = true;
  success &= Firebase.setInt(firebaseData, basePath + "/gasAnalog", gasAnalog);
  success &= Firebase.setFloat(firebaseData, basePath + "/toePressure", toeP);
  success &= Firebase.setFloat(firebaseData, basePath + "/heelPressure", heelP);
  success &= Firebase.setFloat(firebaseData, basePath + "/midfootPressure", midP);
  success &= Firebase.setBool(firebaseData, basePath + "/footDetected", footDetected);
  success &= Firebase.setBool(firebaseData, basePath + "/isSterilizing", isSterilizing);
  success &= Firebase.setFloat(firebaseData, basePath + "/temperatureC", t);
  success &= Firebase.setFloat(firebaseData, basePath + "/humidityPct", h);
  success &= Firebase.setInt(firebaseData, basePath + "/uptime", millis() / 1000);

  if (success) {
    Serial.println("Right Shoe: Firebase update SUCCESS!");
  } else {
    Serial.println("Right Shoe: Firebase update FAILED");
    Serial.println(firebaseData.errorReason());
  }
}
