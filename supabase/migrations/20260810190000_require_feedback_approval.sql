-- New submissions stay hidden until they are approved in the Supabase Table Editor.
alter table public.feedback_posts
    alter column is_published set default false;

update public.feedback_posts
set is_published = false
where status = 'under_review';

drop policy if exists "Anonymous users can submit feedback"
on public.feedback_posts;

create policy "Anonymous users can submit feedback for review"
on public.feedback_posts for insert
to authenticated
with check (
    coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
    and is_published = false
    and status = 'under_review'
);
