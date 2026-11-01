(function(){
  const client=window.amuletSupabase;
  const salonSlug=(window.AMULET_CONFIG&&window.AMULET_CONFIG.SALON_SLUG)||"amulet";
  const form=document.getElementById("customerReviewForm");
  if(!client||!form)return;
  const reviewsBox=document.getElementById("communityReviews");
  const mineBox=document.getElementById("myReviews");
  const submit=form.querySelector("#reviewSubmitButton");
  let session=null,authMode="login",editingId=null;
  const stats={};
  const $=id=>document.getElementById(id);
  const esc=v=>String(v??"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll('"',"&quot;").replaceAll("'","&#039;");
  const accountMsg=(s,bad=false)=>{ $("reviewAccountFeedback").textContent=s||"";$("reviewAccountFeedback").classList.toggle("error",!!bad); };
  const reviewMsg=(s,bad=false)=>{ $("reviewFeedback").textContent=s||"";$("reviewFeedback").classList.toggle("error",!!bad); };
  const displayName=()=>String(session?.user?.user_metadata?.full_name||session?.user?.email?.split("@")[0]||"Відвідувач").slice(0,50);

  window.setReviewAuthMode=function(mode){
    authMode=mode;
    $("reviewSignupNameWrap").style.display=mode==="signup"?"block":"none";
    $("reviewAuthSubmit").textContent=mode==="signup"?"Зареєструватися":"Увійти";
    $("reviewAuthPassword").autocomplete=mode==="signup"?"new-password":"current-password";
    $("reviewLoginTab").classList.toggle("active",mode==="login");
    $("reviewSignupTab").classList.toggle("active",mode==="signup");
    accountMsg("");
  };
  window.submitReviewAuth=async function(){
    const email=$("reviewAuthEmail").value.trim(),password=$("reviewAuthPassword").value;
    if(!email||password.length<8){accountMsg("Вкажіть email і пароль не коротший за 8 символів.",true);return;}
    const btn=$("reviewAuthSubmit");btn.disabled=true;
    try{
      if(authMode==="signup"){
        const name=$("reviewAuthName").value.trim();
        if(name.length<2){accountMsg("Вкажіть ім’я (не менше 2 символів).",true);return;}
        const r=await client.auth.signUp({email,password,options:{data:{full_name:name}}});
        if(r.error)throw r.error;
        if(r.data.session){accountMsg("Акаунт створено. Ви увійшли.");await sync();}
        else accountMsg("Реєстрацію створено. Підтвердьте email, якщо Supabase надіслав лист.");
      }else{
        const r=await client.auth.signInWithPassword({email,password});if(r.error)throw r.error;
        accountMsg("Вхід виконано.");await sync();
      }
    }catch(e){accountMsg("Не вдалося виконати дію: "+e.message,true);}
    finally{btn.disabled=false;}
  };
  window.signOutReviewAccount=async function(){await client.auth.signOut();session=null;editingId=null;form.reset();reviewMsg("");await sync();};

  async function sync(){
    const r=await client.auth.getSession();session=r.data.session||null;
    $("reviewSignedOut").style.display=session?"none":"block";
    $("reviewSignedIn").style.display=session?"block":"none";
    $("reviewSignedName").textContent=session?displayName():"";
    $("reviewSignedEmail").textContent=session?.user?.email||"";
    form.querySelectorAll("input,select,textarea,button").forEach(el=>{
      if(el.name==="company")return;
      el.disabled=!session;
    });
    if(submit)submit.disabled=!session;
    if(session){await loadMine();await loadNotifications();}
    else{mineBox.innerHTML="";$("reviewNotificationArea").innerHTML="";}
    await loadApproved();
  }

  async function loadStats(type,ids){
    if(!ids.length)return;
    const r=await client.from("content_reactions").select("target_type,target_id,user_id").eq("target_type",type).in("target_id",ids);
    if(r.error)return;
    ids.forEach(id=>stats[type+":"+id]={count:0,liked:false});
    (r.data||[]).forEach(x=>{
      const k=type+":"+x.target_id,s=stats[k]||(stats[k]={count:0,liked:false});
      s.count++;if(session&&x.user_id===session.user.id)s.liked=true;
    });
  }
  function controls(type,id,extra=""){
    const s=stats[type+":"+id]||{count:0,liked:false};
    return '<div class="review-actions"><button type="button" class="review-action-button" onclick="toggleReviewReaction(\''+type+'\',\''+id+'\')">👍 '+s.count+(s.liked?" · Ваше":"")+'</button><button type="button" class="review-action-button" onclick="reportReviewContent(\''+type+'\',\''+id+'\')">Поскаржитися</button>'+extra+'</div>';
  }
  window.toggleReviewReaction=async function(type,id){
    if(!session){accountMsg("Увійдіть, щоб поставити реакцію.",true);$("reviewAccount").scrollIntoView({behavior:"smooth"});return;}
    const old=await client.from("content_reactions").select("id").eq("target_type",type).eq("target_id",id).eq("user_id",session.user.id).maybeSingle();
    if(old.error){reviewMsg("Не вдалося перевірити реакцію: "+old.error.message,true);return;}
    const r=old.data?await client.from("content_reactions").delete().eq("id",old.data.id):await client.from("content_reactions").insert({target_type:type,target_id:id,user_id:session.user.id});
    if(r.error){reviewMsg("Не вдалося змінити реакцію: "+r.error.message,true);return;}
    await loadApproved();
  };
  window.reportReviewContent=async function(type,id){
    if(!session){accountMsg("Увійдіть, щоб надіслати скаргу.",true);return;}
    const reason=prompt("Причина скарги (спам, образи, порушення правил, інше):","Спам");if(!reason)return;
    const r=await client.from("content_reports").insert({target_type:type,target_id:id,reporter_id:session.user.id,reason:reason.trim().slice(0,80)});
    if(r.error){reviewMsg("Не вдалося надіслати скаргу: "+r.error.message,true);return;}
    reviewMsg("Скаргу передано адміністрації.");
  };

  function commentNode(reviewId,c,children,depth=0){
    const own=session&&c.author_id===session.user.id;
    const ownBtns=own?'<button type="button" class="review-action-button" onclick="editReviewComment(\''+c.id+'\')">Редагувати</button><button type="button" class="review-action-button" onclick="deleteReviewComment(\''+c.id+'\',\''+reviewId+'\')">Видалити</button>':"";
    const kids=children[c.id]||[];
    return '<div class="review-comment" style="margin-left:'+Math.min(depth,5)*12+'px"><strong>'+esc(c.author_name)+'</strong><span class="review-date"> · '+new Date(c.created_at).toLocaleString("uk-UA")+(c.updated_at&&c.updated_at!==c.created_at?' · редаговано':'')+'</span><p>'+esc(c.body)+'</p>'+controls("review_comment",c.id,'<button type="button" class="review-action-button" onclick="replyReviewComment(\''+reviewId+'\',\''+c.id+'\')">Відповісти</button>'+ownBtns)+'<div class="review-comment-form" id="reviewCommentForm-'+reviewId+'-'+c.id+'"><textarea maxlength="1500" placeholder="Ваш коментар…"></textarea><button type="button" class="review-action-button" onclick="sendReviewComment(\''+reviewId+'\',\''+c.id+'\')">Надіслати</button></div>'+(kids.length?kids.map(x=>commentNode(reviewId,x,children,depth+1)).join(""):"")+'</div>';
  }
  async function loadComments(reviewId){
    const host=$("reviewComments-"+reviewId);if(!host)return;
    const r=await client.rpc("get_public_review_comments",{p_salon_slug:salonSlug,p_review_id:reviewId});
    if(r.error){host.innerHTML='<p class="review-feedback error">Не вдалося завантажити обговорення.</p>';return;}
    const rows=r.data||[];await loadStats("review_comment",rows.map(x=>x.id));
    const children={};rows.forEach(x=>{const k=x.parent_id||"root";(children[k]||(children[k]=[])).push(x);});
    host.innerHTML=(children.root||[]).map(x=>commentNode(reviewId,x,children)).join("")+
      '<div class="review-comment-form open" id="reviewCommentForm-'+reviewId+'-root"><textarea maxlength="1500" placeholder="Додайте коментар до відгуку…"></textarea><button type="button" class="review-action-button" onclick="sendReviewComment(\''+reviewId+'\')">Надіслати коментар</button></div>';
  }
  window.replyReviewComment=function(reviewId,parentId){
    if(!session){accountMsg("Увійдіть, щоб відповідати.",true);return;}
    const f=$("reviewCommentForm-"+reviewId+"-"+parentId);if(f){f.classList.toggle("open");if(f.classList.contains("open"))f.querySelector("textarea").focus();}
  };
  window.sendReviewComment=async function(reviewId,parentId=""){
    if(!session){accountMsg("Увійдіть, щоб коментувати.",true);return;}
    const f=$("reviewCommentForm-"+reviewId+"-"+(parentId||"root"));if(!f)return;
    const area=f.querySelector("textarea"),body=area.value.trim();if(body.length<2){area.focus();return;}
    const payload={review_id:reviewId,author_id:session.user.id,author_name:displayName(),body,status:"published"};
    if(parentId)payload.parent_id=parentId;
    const r=await client.from("review_comments").insert(payload);
    if(r.error){reviewMsg("Не вдалося додати коментар: "+r.error.message,true);return;}
    await loadComments(reviewId);await loadNotifications();
  };
  window.editReviewComment=async function(id){
    if(!session)return;
    const x=await client.from("review_comments").select("id,author_id,body").eq("id",id).maybeSingle();
    if(x.error||!x.data||x.data.author_id!==session.user.id)return;
    const body=prompt("Змінити коментар:",x.data.body);if(body===null)return;
    const r=await client.rpc("update_review_comment_content",{p_comment_id:id,p_body:body});
    if(r.error){reviewMsg("Не вдалося відредагувати коментар: "+r.error.message,true);return;}
    await loadApproved();
  };
  window.deleteReviewComment=async function(id,reviewId){
    if(!session||!confirm("Видалити свій коментар разом із відповідями?"))return;
    const r=await client.from("review_comments").delete().eq("id",id).eq("author_id",session.user.id);
    if(r.error){reviewMsg("Не вдалося видалити коментар: "+r.error.message,true);return;}
    await loadComments(reviewId);
  };

  function reviewCard(x){
    const own=session&&x.author_id===session.user.id;
    const owner=own?'<button type="button" class="review-action-button" onclick="editCustomerReview(\''+x.id+'\')">Редагувати</button><button type="button" class="review-action-button" onclick="deleteCustomerReview(\''+x.id+'\')">Видалити</button>':"";
    return '<article class="review-card glass-card community-review-card" id="customer-review-'+x.id+'"><div class="review-stars">'+("★".repeat(Number(x.rating)||0))+'</div><p class="review-text">'+esc(x.review_text)+'</p><div class="review-author"><div class="author-info"><h4>'+esc(x.customer_name)+'</h4><span>'+new Date(x.created_at).toLocaleDateString("uk-UA")+'</span></div></div>'+controls("customer_review",x.id,owner)+'<div class="review-comments"><strong>Обговорення</strong><div id="reviewComments-'+x.id+'"><div class="review-feedback">Завантаження…</div></div></div></article>';
  }
  async function loadApproved(){
    const r=await client.rpc("get_public_approved_reviews",{p_salon_slug:salonSlug});
    if(r.error){console.warn("Approved reviews unavailable:",r.error.message);return;}
    await loadStats("customer_review",(r.data||[]).map(x=>x.id));
    reviewsBox.innerHTML=(r.data||[]).map(reviewCard).join("");
    for(const x of r.data||[])await loadComments(x.id);
  }
  async function loadMine(){
    const r=await client.from("customer_reviews").select("id,customer_name,rating,review_text,created_at,status,author_id").eq("author_id",session.user.id).order("created_at",{ascending:false}).limit(30);
    if(r.error){mineBox.innerHTML="";return;}
    const mine=(r.data||[]).filter(x=>x.status!=="approved");
    mineBox.innerHTML=mine.length?'<h3 class="section-title">Мої відгуки на перевірці</h3>'+mine.map(x=>'<article class="review-card glass-card pending-review"><span class="tag">'+(x.status==="pending"?"Очікує модерації":"Відхилено — можна змінити й надіслати знову")+'</span><h4>'+esc(x.customer_name)+'</h4><div class="review-stars">'+("★".repeat(Number(x.rating)||0))+'</div><p class="review-text">'+esc(x.review_text)+'</p><button type="button" class="review-action-button" onclick="editCustomerReview(\''+x.id+'\')">Редагувати</button><button type="button" class="review-action-button" onclick="deleteCustomerReview(\''+x.id+'\')">Видалити</button></article>').join(""):"";
  }
  window.editCustomerReview=async function(id){
    if(!session)return;
    const r=await client.from("customer_reviews").select("id,author_id,customer_name,rating,review_text").eq("id",id).eq("author_id",session.user.id).maybeSingle();
    if(r.error||!r.data)return;
    editingId=id;$("reviewCustomerName").value=r.data.customer_name;$("reviewRating").value=String(r.data.rating);$("reviewMessage").value=r.data.review_text;
    if(submit)submit.textContent="Зберегти зміни й надіслати на перевірку";
    form.scrollIntoView({behavior:"smooth",block:"center"});
  };
  window.deleteCustomerReview=async function(id){
    if(!session||!confirm("Видалити свій відгук разом з обговоренням?"))return;
    const r=await client.from("customer_reviews").delete().eq("id",id).eq("author_id",session.user.id);
    if(r.error){reviewMsg("Не вдалося видалити відгук: "+r.error.message,true);return;}
    if(editingId===id){editingId=null;form.reset();if(submit)submit.textContent="Надіслати відгук";}
    await sync();
  };
  async function loadNotifications(){
    if(!session)return;
    const r=await client.from("user_notifications").select("id,message,target_type,target_id,created_at,read_at").eq("recipient_id",session.user.id).order("created_at",{ascending:false}).limit(20);
    const area=$("reviewNotificationArea");if(r.error){area.innerHTML="";return;}
    const rows=r.data||[],unread=rows.filter(x=>!x.read_at).length;
    area.innerHTML='<h4 style="margin:14px 0 6px">Сповіщення · '+unread+'</h4>'+(rows.length?rows.map(x=>'<div class="review-notification">'+esc(x.message)+'<div class="review-date">'+new Date(x.created_at).toLocaleString("uk-UA")+'</div><button type="button" class="review-action-button" onclick="openReviewNotification(\''+x.id+'\',\''+x.target_type+'\',\''+x.target_id+'\')">'+(x.read_at?"Відкрити":"Позначити прочитаним")+'</button></div>').join(""):'<p class="review-feedback">Сповіщень поки немає.</p>');
  }
  window.openReviewNotification=async function(id,type,target){
    await client.from("user_notifications").update({read_at:new Date().toISOString()}).eq("id",id);
    let reviewId=target;
    if(type==="review_comment"){const q=await client.from("review_comments").select("review_id").eq("id",target).maybeSingle();if(q.data)reviewId=q.data.review_id;}
    await loadApproved();const card=$("customer-review-"+reviewId);if(card)card.scrollIntoView({behavior:"smooth",block:"center"});await loadNotifications();
  };

  form.addEventListener("submit",async function(event){
    event.preventDefault();event.stopImmediatePropagation();reviewMsg("");
    if(!session){accountMsg("Спочатку увійдіть або створіть акаунт.",true);$("reviewAccount").scrollIntoView({behavior:"smooth"});return;}
    const values=new FormData(form);if(String(values.get("company")||"").trim()){form.reset();return;}
    const payload={customer_name:String(values.get("customer_name")||"").trim(),rating:Number(values.get("rating")),review_text:String(values.get("review_text")||"").trim()};
    if(payload.customer_name.length<2||payload.customer_name.length>60||!Number.isInteger(payload.rating)||payload.rating<1||payload.rating>5||payload.review_text.length<5||payload.review_text.length>1500){reviewMsg("Перевірте ім’я, оцінку та текст відгуку.",true);return;}
    const old=submit?submit.innerHTML:"";if(submit){submit.disabled=true;submit.textContent="Надсилання…";}
    try{
      const r=editingId
        ?await client.rpc("update_customer_review_content",{p_review_id:editingId,p_customer_name:payload.customer_name,p_rating:payload.rating,p_review_text:payload.review_text})
        :await client.rpc("submit_customer_review",{
          p_salon_slug:salonSlug,
          p_customer_name:payload.customer_name,
          p_rating:payload.rating,
          p_review_text:payload.review_text
        });
      if(r.error)throw r.error;
      editingId=null;form.reset();if(submit)submit.innerHTML='<i class="fa-solid fa-paper-plane"></i> Надіслати відгук';
      reviewMsg("Дякуємо! Відгук надіслано на перевірку. Він з’явиться на сайті після схвалення.");
      await sync();
    }catch(e){reviewMsg("Не вдалося надіслати відгук: "+e.message,true);}
    finally{if(submit){submit.disabled=!session;if(editingId)submit.textContent="Зберегти зміни й надіслати на перевірку";else if(submit.textContent==="Надсилання…")submit.innerHTML=old;}}
  },true);

  sync();
  client.auth.onAuthStateChange(()=>{setTimeout(sync,0);});
})();