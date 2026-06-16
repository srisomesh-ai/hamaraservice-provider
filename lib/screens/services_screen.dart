import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/theme.dart';
import '../services/hs_catalog.dart';

// Simple provider services selection screen
// Provider just toggles which services they offer — nothing else
class ServicesScreen extends StatefulWidget {
  final String providerId;
  const ServicesScreen({super.key, required this.providerId});
  @override
  State<ServicesScreen> createState() => _State();
}

class _State extends State<ServicesScreen> {
  Set<String> _on = {};
  bool _loading = true;
  bool _saving  = false;
  String _cat   = 'All';

  static const _cats = [
    'All','Home Cleaning','Home Services','Vehicle Care',
    'Cooking','Beauty & Wellness','Health Services',
    'Care Services','Outdoor','Security','Pest Control',
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('providers/${widget.providerId}/services').get();
      if (snap.exists) {
        final d = Map<String,dynamic>.from(snap.value as Map);
        _on = d.entries.where((e)=>e.value==true).map((e)=>e.key).toSet();
      }
    } catch (_) {}
    if (mounted) setState(()=>_loading=false);
  }

  Future<void> _save() async {
    setState(()=>_saving=true);
    HapticFeedback.mediumImpact();
    try {
      final Map<String,dynamic> u={};
      for (final s in HSCatalog.services) u[s.id]=_on.contains(s.id);
      await FirebaseDatabase.instance
          .ref('providers/${widget.providerId}/services').update(u);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved — ${_on.length} services'),
          backgroundColor: AppColors.green));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: AppColors.red));
    }
    if (mounted) setState(()=>_saving=false);
  }

  List<HSService> get _list => _cat=='All'
      ? HSCatalog.services
      : HSCatalog.services.where((s)=>s.cat==_cat).toList();

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: AppColors.teal)));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('My Services',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          Text('${_on.length} selected',
            style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16),
              child: SizedBox(width:20,height:20,
                child: CircularProgressIndicator(color:Colors.white,strokeWidth:2)))
          else
            TextButton(
              onPressed: _save,
              child: const Text('SAVE',
                style: TextStyle(color:Colors.white,
                  fontWeight:FontWeight.w800,fontSize:14))),
        ]),
      body: Column(children: [
        // Category filter
        Container(color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical:8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal:12),
            child: Row(children: _cats.map((c){
              final sel = _cat==c;
              return GestureDetector(
                onTap: ()=>setState(()=>_cat=c),
                child: Container(
                  margin: const EdgeInsets.only(right:8),
                  padding: const EdgeInsets.symmetric(horizontal:12,vertical:6),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.teal : AppColors.bg,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: sel ? AppColors.teal : AppColors.line)),
                  child: Text(c, style: TextStyle(fontSize:11,
                    fontWeight:FontWeight.w700,
                    color: sel ? Colors.white : AppColors.muted))));
            }).toList()))),
        // Quick actions
        Container(color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12,0,12,8),
          child: Row(children: [
            TextButton(
              onPressed: ()=>setState((){
                _on=HSCatalog.services.map((s)=>s.id).toSet();}),
              child: const Text('Select All',
                style: TextStyle(fontSize:12,color:AppColors.teal,
                  fontWeight:FontWeight.w700))),
            const Text('·',style:TextStyle(color:AppColors.muted)),
            TextButton(
              onPressed: ()=>setState(()=>_on.clear()),
              child: const Text('Clear All',
                style: TextStyle(fontSize:12,color:AppColors.red,
                  fontWeight:FontWeight.w700))),
          ])),
        // List
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12,8,12,100),
          itemCount: _list.length,
          itemBuilder: (_,i)=>_card(_list[i]))),
      ]),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16,10,16,28),
        color: Colors.white,
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teal,
            minimumSize: const Size(double.infinity,50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12))),
          child: Text('Save ${_on.length} Services',
            style: const TextStyle(fontSize:14,
              fontWeight:FontWeight.w700,color:Colors.white)))));
  }

  Widget _card(HSService svc) {
    final on = _on.contains(svc.id);
    return GestureDetector(
      onTap: (){
        HapticFeedback.selectionClick();
        setState((){
          if(on) _on.remove(svc.id); else _on.add(svc.id);
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom:8),
        padding: const EdgeInsets.symmetric(horizontal:14,vertical:12),
        decoration: BoxDecoration(
          color: on ? AppColors.tealSoft : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: on ? AppColors.teal : AppColors.line,
            width: on ? 2 : 1),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04), blurRadius:6)]),
        child: Row(children: [
          // Icon
          Container(width:46,height:46,
            decoration: BoxDecoration(
              color: on ? AppColors.teal.withOpacity(0.12) : AppColors.bg,
              borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(svc.icon,
              style: const TextStyle(fontSize:24)))),
          const SizedBox(width:12),
          // Name + category
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(svc.name, style: TextStyle(fontSize:14,
              fontWeight:FontWeight.w700,
              color: on ? AppColors.teal : AppColors.ink)),
            Text(svc.cat, style: const TextStyle(
              fontSize:11,color:AppColors.muted)),
          ])),
          // Toggle
          Switch(
            value: on,
            onChanged: (v){
              HapticFeedback.selectionClick();
              setState((){
                if(v) _on.add(svc.id); else _on.remove(svc.id);
              });
            },
            activeColor: AppColors.teal,
            activeTrackColor: AppColors.tealSoft),
        ])));
  }
}
