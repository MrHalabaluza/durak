import '../connection.dart';
import '../protocol.dart';
import 'auth_service.dart';

typedef Dispatch = void Function(Connection conn, ClientMessage msg);

Dispatch authedDispatch(AuthService auth, Dispatch inner) {
  return (conn, msg) {
    if (!conn.authed) {
      if (msg is AuthMsg) {
        final u = auth.resolveToken(msg.token);
        if (u == null) {
          print('[auth] bad_token');
          conn.send(errorMsg('bad_token'));
          conn.close();
          return;
        }
        conn.markAuthed(u.id, u.username);
        conn.send(authOkMsg(u.id, u.username));
      } else {
        conn.send(errorMsg('not_authed'));
      }
      return;
    }
    inner(conn, msg);
  };
}
