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

FirebaseData firebaseData;
FirebaseAuth auth;
FirebaseConfig config;

unsigned long lastUpdate = 0;

void setup() {
  Serial.begin(115200);
  
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
  if (millis() - lastUpdate >= 5000) {
    lastUpdate = millis();
    updateFirebase();
  }
}

void updateFirebase() {
  int gasAnalog = analogRead(MQ135_PIN);
  if (gasAnalog < 100) gasAnalog = 0; // Noise gate for floating pins

  double toeP = analogRead(FSR_TOE_PIN) * (10.0 / 4095.0); 
  if (toeP < 0.2) toeP = 0;
  
  double heelP = analogRead(FSR_HEEL_PIN) * (10.0 / 4095.0);
  if (heelP < 0.2) heelP = 0;
  
  double midP = analogRead(FSR_MID_PIN) * (10.0 / 4095.0);
  if (midP < 0.2) midP = 0;
  bool footDetected = (toeP > 1.0 || heelP > 1.0);

  String basePath = String("/devices/") + SYSTEM_ID + "/left_shoe";
  
  bool success = true;
  success &= Firebase.setInt(firebaseData, basePath + "/gasAnalog", gasAnalog);
  success &= Firebase.setFloat(firebaseData, basePath + "/toePressure", toeP);
  success &= Firebase.setFloat(firebaseData, basePath + "/heelPressure", heelP);
  success &= Firebase.setFloat(firebaseData, basePath + "/midfootPressure", midP);
  success &= Firebase.setBool(firebaseData, basePath + "/footDetected", footDetected);
  success &= Firebase.setInt(firebaseData, basePath + "/uptime", millis() / 1000);

  if (success) {
    Serial.println("Left Shoe: Firebase update SUCCESS!");
  } else {
    Serial.println("Left Shoe: Firebase update FAILED");
    Serial.println(firebaseData.errorReason());
  }
}
