import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'gujarat_data.dart';
import 'location_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CityPickerScreen extends StatelessWidget {
  const CityPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Select city'),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        titleTextStyle: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      body: ListView.builder(
        itemCount: kStates.length,
        itemBuilder: (context, stateIndex) {
          final state = kStates[stateIndex];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Text(
                  state.name.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12),
                ),
              ),
              ...state.cities.map((city) {
                final isEnabled = city.enabled;
                final isSelected = context.watch<LocationService>().cityId == city.id;
                
                return ListTile(
                  title: Text(
                    city.name,
                    style: TextStyle(color: isEnabled ? Colors.black87 : Colors.grey),
                  ),
                  trailing: isSelected 
                    ? const Icon(Icons.check, color: Colors.blue) 
                    : (isEnabled ? null : const Text('Coming soon', style: TextStyle(color: Colors.grey, fontSize: 12))),
                  onTap: () {
                    if (isEnabled) {
                      context.read<LocationService>().setCity(city);
                      Navigator.pop(context);
                    } else {
                      _joinWaitlist(context, city.id, city.name);
                    }
                  },
                );
              }),
            ],
          );
        },
      ),
    );
  }

  void _joinWaitlist(BuildContext context, String cityId, String cityName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('city_waitlist').doc('${cityId}_${user.uid}').set({
        'cityId': cityId,
        'uid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Joined waitlist for $cityName! We will notify you when we launch.')),
      );
    }
  }
}
