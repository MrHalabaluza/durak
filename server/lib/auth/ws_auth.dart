import 'package:durak_logic/durak_logic.dart';
import '../connection.dart';
import '../protocol.dart';
import '../db/deck_dao.dart';
import 'auth_service.dart';

typedef Dispatch = void Function(Connection conn, ClientMessage msg);

Dispatch authedDispatch(AuthService auth, DeckDao deckDao, Dispatch inner) {
  return (conn, msg) {
    if (!conn.authed) {
      if (msg is AuthMsg) {
        final u = auth.resolveToken(msg.token);
        if (u == null) {
          conn.send(errorMsg('bad_token'));
          conn.close();
          return;
        }
        conn.markAuthed(u.id, u.username);
        conn.savedDeckConfig = deckDao.load(u.id) ?? DeckConfig();
        conn.send(authOkMsg(u.id, u.username, conn.savedDeckConfig));
      } else {
        conn.send(errorMsg('not_authed'));
      }
      return;
    }
    inner(conn, msg);
  };
}
