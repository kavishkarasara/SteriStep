#include <WiFi.h>
#include <FirebaseESP32.h>
#include <DHT.h>

#define WIFI_SSID "BELL4G"
#define WIFI_PASSWORD "Brothers123"

#define FIREBASE_HOST "sterstep-cfeed-default-rtdb.firebaseio.com"
#define FIREBASE_AUTH "krvZo8Lp9460s5p9parhlRVFAecENffjzd8rl0zp"
#define SYSTEM_ID "steristep_001" // UNIQUE ID FOR THIS PHYSICAL DEVICE

// Pins for ESP32-S3
#define DHT_PIN 5
#define DHT_TYPE DHT22

#define RELAY_UVC 6
#define RELAY_MIST 7
#define RELAY_FAN 8
#define REED_SWITCH 9
#define BUZZER_PIN 10

DHT dht(DHT_PIN, DHT_TYPE);
FirebaseData firebaseData;
FirebaseAuth auth;
FirebaseConfig config;

unsigned long lastUpdate = 0;
String cabinetStatus = "Idle";
bool isSterilizing = false;
unsigned long sterilizationStartTime = 0;
int sterilizationProgress = 0;
String basePath = String("/devices/") + SYSTEM_ID + "/cabinet";

void setup() {
  Serial.begin(115200);
  
  pinMode(RELAY_UVC, OUTPUT);
  pinMode(RELAY_MIST, OUTPUT);
  pinMode(RELAY_FAN, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(REED_SWITCH, INPUT_PULLUP);

  // Relays OFF initially (Assuming Active HIGH, change to HIGH if Active LOW)
  digitalWrite(RELAY_UVC, LOW);
  digitalWrite(RELAY_MIST, LOW);
  digitalWrite(RELAY_FAN, LOW);
  digitalWrite(BUZZER_PIN, LOW);
  
  dht.begin();
  
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

void loop() {
  // Check for commands from app
  if (Firebase.getString(firebaseData, basePath + "/command")) {
    String cmd = firebaseData.stringData();
    if (cmd == "START_UVC" && !isSterilizing) {
      isSterilizing = true;
      cabinetStatus = "UVC Sterilizing";
      digitalWrite(RELAY_UVC, HIGH);
      digitalWrite(RELAY_FAN, HIGH);
      sterilizationStartTime = millis();
      sterilizationProgress = 0;
      Firebase.setString(firebaseData, basePath + "/command", "IDLE"); // Clear command
    } 
    else if (cmd == "START_HEAVY" && !isSterilizing) {
      isSterilizing = true;
      cabinetStatus = "UVC+H2O2 Sterilizing";
      digitalWrite(RELAY_UVC, HIGH);
      digitalWrite(RELAY_MIST, HIGH);
      digitalWrite(RELAY_FAN, HIGH);
      sterilizationStartTime = millis();
      sterilizationProgress = 0;
      Firebase.setString(firebaseData, basePath + "/command", "IDLE"); // Clear command
    }
  }

  // Sterilization Timer Logic
  if (isSterilizing) {
    unsigned long elapsed = millis() - sterilizationStartTime;
    sterilizationProgress = (elapsed * 100) / 60000; // 60s total
    if (sterilizationProgress > 100) sterilizationProgress = 100;

    if (elapsed > 60000) { // 1 min sterilization for demo
      isSterilizing = false;
      cabinetStatus = "Done";
      sterilizationProgress = 100;
      digitalWrite(RELAY_UVC, LOW);
      digitalWrite(RELAY_MIST, LOW);
      digitalWrite(RELAY_FAN, LOW);
      digitalWrite(BUZZER_PIN, HIGH);
      delay(1000); // Beep to indicate done
      digitalWrite(BUZZER_PIN, LOW);
    }
  }

  // Push data every 5 seconds
  if (millis() - lastUpdate >= 5000) {
    lastUpdate = millis();
    updateFirebase();
  }
}

void updateFirebase() {
  double t = dht.readTemperature();
  double h = dht.readHumidity();
  if (isnan(t)) t = 0;
  if (isnan(h)) h = 0;
  
  int doorStatus = digitalRead(REED_SWITCH); // 0 = Closed, 1 = Open
  
  bool success = true;
  success &= Firebase.setFloat(firebaseData, basePath + "/temperatureC", t);
  success &= Firebase.setFloat(firebaseData, basePath + "/humidityPct", h);
  success &= Firebase.setString(firebaseData, basePath + "/cabinetStatus", cabinetStatus);
  success &= Firebase.setInt(firebaseData, basePath + "/progress", sterilizationProgress);
  success &= Firebase.setInt(firebaseData, basePath + "/doorOpen", doorStatus);
  success &= Firebase.setInt(firebaseData, basePath + "/uptime", millis() / 1000);

  if (success) {
    Serial.println("Cabinet: Firebase update SUCCESS!");
  } else {
    Serial.println("Cabinet: Firebase update FAILED");
    Serial.println(firebaseData.errorReason());
  }
}
