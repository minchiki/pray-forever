package com.prayforever.app

import android.app.Application
import com.prayforever.app.alarm.AlarmController

class PrayerApp : Application() {
    override fun onCreate() {
        super.onCreate()
        AlarmController.init(this)
    }
}
